const std = @import("std");
const limine = @import("../limine_import.zig").C;
const serial = @import("../kernel/serial.zig");
// const layout = @import("layout.zig");

// Externs from limine.c
pub extern var memmap_request: limine.struct_limine_memmap_request;
pub extern var hhdm_request: limine.struct_limine_hhdm_request;

var bitmap: []u8 = &[_]u8{};
var bitmap_phys_base: u64 = 0;
var last_used_index: usize = 0;
var total_pages: usize = 0;

const PAGE_SIZE: u64 = 4096;

/// Initializes the Physical Memory Manager (PMM).
/// Parses the Limine memory map, sets up the allocation bitmap, and reserves kernel/used memory.
pub fn init() void {
    const memmap_resp = memmap_request.response;
    const hhdm_resp = hhdm_request.response;

    if (memmap_resp == null or hhdm_resp == null) {
        serial.err("PMM: Bootloader responses missing (Memmap or HHDM). Halting.");
        while (true) {}
    }

    const entry_count = memmap_resp.*.entry_count;
    const entries = memmap_resp.*.entries;
    const hhdm_offset = hhdm_resp.*.offset;

    serial.info("PMM: Initializing...");

    // 1. Calculate max memory to determine bitmap size
    var max_address: u64 = 0;

    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        const entry = entries[i];
        const type_name = getMemmapType(entry.*.type);

        // Logging memory map for debug
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Region: Base=0x{x} Len=0x{x} Type={s}", .{ entry.*.base, entry.*.length, type_name }) catch "Fmt Error";
        serial.debug(msg);

        if (entry.*.type == limine.LIMINE_MEMMAP_USABLE or
            entry.*.type == limine.LIMINE_MEMMAP_BOOTLOADER_RECLAIMABLE or
            entry.*.type == limine.LIMINE_MEMMAP_EXECUTABLE_AND_MODULES) // Kernel is technically "used" but exists in RAM
        {
            const end = entry.*.base + entry.*.length;
            if (end > max_address) max_address = end;
        }
    }

    total_pages = max_address / PAGE_SIZE;
    const bitmap_size = std.math.divCeil(usize, total_pages, 8) catch unreachable;

    // 2. Find a place for the bitmap
    // We look for a USABLE region large enough to hold the bitmap.
    var bitmap_found = false;
    i = 0;
    while (i < entry_count) : (i += 1) {
        const entry = entries[i];
        if (entry.*.type == limine.LIMINE_MEMMAP_USABLE) {
            if (entry.*.length >= bitmap_size) {
                bitmap_phys_base = entry.*.base;
                // We access the bitmap via HHDM (Higher Half Direct Map)
                const bitmap_virt_addr = bitmap_phys_base + hhdm_offset;
                bitmap = @as([*]u8, @ptrFromInt(bitmap_virt_addr))[0..bitmap_size];

                // Initialize bitmap: Mark EVERYTHING as used (1) first (safe default)
                @memset(bitmap, 0xFF);

                bitmap_found = true;
                break;
            }
        }
    }

    if (!bitmap_found) {
        serial.err("PMM: Could not find memory for bitmap! Halting.");
        while (true) {}
    }

    serial.info("PMM: Bitmap placed at phys 0x");
    serial.printHex(.info, bitmap_phys_base);

    // 3. Populate Bitmap based on Memory Map
    // Now iterate again and mark USABLE regions as free (0)
    i = 0;
    while (i < entry_count) : (i += 1) {
        const entry = entries[i];
        if (entry.*.type == limine.LIMINE_MEMMAP_USABLE) {
            freeRegion(entry.*.base, entry.*.length);
        }
    }

    // 4. Mark the bitmap ITSELF as used!
    // We just freed the region containing the bitmap in step 3, so now we must re-lock it.
    reserveRegion(bitmap_phys_base, bitmap_size);

    // 5. Reserve the first 1MB (legacy VGA etc) just to be safe
    reserveRegion(0, 0x100000);

    serial.info("PMM: Initialization Complete.");
}

/// Returns a string representation of the Limine memory map type.
fn getMemmapType(type_val: u64) []const u8 {
    return switch (type_val) {
        limine.LIMINE_MEMMAP_USABLE => "USABLE",
        limine.LIMINE_MEMMAP_RESERVED => "RESERVED",
        limine.LIMINE_MEMMAP_ACPI_RECLAIMABLE => "ACPI_RECLAIMABLE",
        limine.LIMINE_MEMMAP_ACPI_NVS => "ACPI_NVS",
        limine.LIMINE_MEMMAP_BAD_MEMORY => "BAD_MEMORY",
        limine.LIMINE_MEMMAP_BOOTLOADER_RECLAIMABLE => "BOOTLOADER_RECLAIMABLE",
        limine.LIMINE_MEMMAP_EXECUTABLE_AND_MODULES => "EXECUTABLE_AND_MODULES",
        limine.LIMINE_MEMMAP_FRAMEBUFFER => "FRAMEBUFFER",
        else => "UNKNOWN",
    };
}

// Helpers
/// Sets the bit at the given index in the bitmap (marking page as used).
fn setBit(index: usize) void {
    const byte_idx = index / 8;
    const bit_idx = @as(u3, @intCast(index % 8));
    bitmap[byte_idx] |= (@as(u8, 1) << bit_idx);
}

/// Clears the bit at the given index in the bitmap (marking page as free).
fn clearBit(index: usize) void {
    const byte_idx = index / 8;
    const bit_idx = @as(u3, @intCast(index % 8));
    bitmap[byte_idx] &= ~(@as(u8, 1) << bit_idx);
}

/// Checks if the bit at the given index is set (page is used).
fn testBit(index: usize) bool {
    const byte_idx = index / 8;
    const bit_idx = @as(u3, @intCast(index % 8));
    return (bitmap[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;
}

/// Marks a range of physical memory as used in the bitmap.
fn reserveRegion(base: u64, length: u64) void {
    const start_page = base / PAGE_SIZE;
    const end_page = (base + length + PAGE_SIZE - 1) / PAGE_SIZE;

    var i = start_page;
    while (i < end_page) : (i += 1) {
        if (i < total_pages) setBit(i);
    }
}

/// Marks a range of physical memory as free in the bitmap.
fn freeRegion(base: u64, length: u64) void {
    const start_page = base / PAGE_SIZE;
    const end_page = (base + length) / PAGE_SIZE; // Truncate down for free (only free full pages)

    var i = start_page;
    while (i < end_page) : (i += 1) {
        if (i < total_pages) clearBit(i);
    }
}

/// Allocates a single page of physical memory.
/// Returns the physical address of the allocated page, or null if OOM.
pub fn allocatePage() ?u64 {
    // Determine where to start searching
    // We can use a roving pointer (last_used_index) to speed up sequential allocations
    var i = last_used_index;

    // First pass: from last_used to end
    while (i < total_pages) : (i += 1) {
        if (!testBit(i)) {
            setBit(i);
            last_used_index = i + 1;
            return @as(u64, i) * PAGE_SIZE;
        }
    }

    // Second pass: from 0 to last_used
    i = 0;
    while (i < last_used_index) : (i += 1) {
        if (!testBit(i)) {
            setBit(i);
            last_used_index = i + 1;
            return @as(u64, i) * PAGE_SIZE;
        }
    }

    return null; // OOM
}

/// Frees a previously allocated page of physical memory given its physical address.
pub fn freePage(phys_addr: u64) void {
    const page_idx = phys_addr / PAGE_SIZE;
    if (page_idx < total_pages) {
        clearBit(page_idx);
        // Optimization: Reset last_used_index?
        // Usually safer to not move it backwards excessively,
        // but if we freed something lower, we could hint it.
        // For now, keep it simple.
        if (page_idx < last_used_index) {
            last_used_index = page_idx;
        }
    }
}

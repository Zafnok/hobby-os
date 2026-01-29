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

pub const PAGE_SIZE: u64 = 4096;

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
    return allocatePages(1);
}

/// Allocates `count` contiguous pages of physical memory.
/// Returns the physical address of the first page, or null if OOM.
pub fn allocatePages(count: usize) ?u64 {
    if (count == 0) return null;

    // Search wrapper to handle wrap-around
    if (findFreeRange(last_used_index, total_pages, count)) |idx| {
        markUsed(idx, count);
        last_used_index = idx + count;
        return @as(u64, idx) * PAGE_SIZE;
    }

    if (findFreeRange(0, last_used_index, count)) |idx| {
        markUsed(idx, count);
        last_used_index = idx + count;
        return @as(u64, idx) * PAGE_SIZE;
    }

    return null; // OOM
}

/// Helper to find a range of free bits.
fn findFreeRange(start_idx: usize, end_limit: usize, count: usize) ?usize {
    var i = start_idx;
    while (i <= end_limit -| count) : (i += 1) { // -| is saturating sub, checking bounds
        // Check if [i ... i+count] are all free
        var all_free = true;
        var j: usize = 0;
        while (j < count) : (j += 1) {
            if (testBit(i + j)) {
                all_free = false;
                // Optimization: Skip ahead
                i += j; // Outer loop does i+=1, so effectively i = i + j + 1
                break;
            }
        }
        if (all_free) return i;
    }
    return null;
}

/// Helper to mark a range as used.
fn markUsed(start_idx: usize, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        setBit(start_idx + i);
    }
}

/// Frees a previously allocated page of physical memory given its physical address.
pub fn freePage(phys_addr: u64) void {
    freePages(phys_addr, 1);
}

/// Frees `count` contiguous pages starting at `phys_addr`.
pub fn freePages(phys_addr: u64, count: usize) void {
    const start_idx = phys_addr / PAGE_SIZE;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const idx = start_idx + i;
        if (idx < total_pages) {
            clearBit(idx);
        }
    }

    // Hint optimization
    if (start_idx < last_used_index) {
        last_used_index = start_idx;
    }
}

test "PMM Allocation and Free" {
    // 1. Verify Basic Page Allocation
    const page1 = allocatePage();
    try std.testing.expect(page1 != null);
    serial.info("Test: Allocated Page 1");

    const page2 = allocatePage();
    try std.testing.expect(page2 != null);
    serial.info("Test: Allocated Page 2");

    // Addresses should be distinct
    try std.testing.expect(page1.? != page2.?);

    freePage(page2.?);
    serial.info("Test: Freed Page 2");

    freePage(page1.?);
    serial.info("Test: Freed Page 1");
}

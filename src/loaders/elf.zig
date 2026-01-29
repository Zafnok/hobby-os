const std = @import("std");
const limine = @import("../limine_import.zig").C;
const serial = @import("../kernel/serial.zig");
const memory = @import("../memory/layout.zig");
const pmm = @import("../memory/pmm.zig");
const vmm = @import("../memory/vmm.zig");

// Use Zig's standard ELF definitions
const Elf64_Ehdr = std.elf.Elf64_Ehdr;
const Elf64_Phdr = std.elf.Elf64_Phdr;

pub const ElfError = error{
    InvalidMagic,
    InvalidClass,
    InvalidEndian,
    InvalidVersion,
    InvalidMachine,
    InvalidType,
    LoadFailed,
};

/// Loads an ELF file from memory into the correct virtual address and returns the entry point.
/// This function assumes the ELF is a position-dependent executable (or position-independent)
/// and loads it exactly where the Program Headers request (unless relocatable, which we don't support yet).
pub fn loadElf(file_ptr: [*]const u8, file_size: u64) !u64 {
    const header = @as(*const Elf64_Ehdr, @ptrCast(@alignCast(file_ptr)));

    // 1. Validation
    if (!std.mem.eql(u8, header.e_ident[0..4], "\x7FELF")) return ElfError.InvalidMagic;
    if (header.e_ident[std.elf.EI_CLASS] != std.elf.ELFCLASS64) return ElfError.InvalidClass;
    if (header.e_ident[std.elf.EI_DATA] != std.elf.ELFDATA2LSB) return ElfError.InvalidEndian;
    if (header.e_machine != std.elf.EM.X86_64) return ElfError.InvalidMachine;
    // We only accept executables or shared objects (PIE)
    if (header.e_type != std.elf.ET.EXEC and header.e_type != std.elf.ET.DYN) return ElfError.InvalidType;

    serial.info("ELFLoader: Header Validated.");

    // 2. Iterate Program Headers
    const ph_offset = header.e_phoff;
    const ph_num = header.e_phnum;
    const ph_size = header.e_phentsize;

    // Validate bounds
    if (ph_offset + ph_num * ph_size > file_size) return ElfError.InvalidMagic; // Corrupt file

    var i: usize = 0;
    while (i < ph_num) : (i += 1) {
        const ph_addr = @intFromPtr(file_ptr) + ph_offset + (i * ph_size);
        const ph: *const Elf64_Phdr = @ptrFromInt(ph_addr);

        if (ph.p_type == std.elf.PT_LOAD) {
            // Load this segment
            try loadSegment(file_ptr, ph);
        }
    }

    return header.e_entry;
}

/// Loads a single ELF program header (PT_LOAD) segment into memory.
///
/// This function allocates physical pages for the segment's memory range,
/// maps them to the requested virtual addresses, copies the data from the file,
/// and zeros out the BSS section (if p_memsz > p_filesz).
///
/// ## Parameters
/// - `file_base`: Pointer to the start of the ELF file in memory
/// - `ph`: Pointer to the ELF Program Header describing this segment
///
/// ## Process
/// 1. Calculate page-aligned start and end addresses from the segment's virtual address
/// 2. Allocate and map physical pages for the entire memory range
/// 3. Copy initialized data from the file (p_filesz bytes)
/// 4. Zero out uninitialized BSS section (p_memsz - p_filesz bytes)
fn loadSegment(file_base: [*]const u8, ph: *const Elf64_Phdr) !void {
    if (ph.p_memsz == 0) return;

    // Destination in memory (Virtual Address)
    const dest_addr = ph.p_vaddr;

    serial.debug("ELFLoader: Loading Segment (VA, Size):");
    serial.printHex(.debug, dest_addr);
    serial.printHex(.debug, ph.p_memsz);

    // Calculate start and end pages
    const page_size: u64 = 0x1000;
    const start_page = dest_addr & ~(page_size - 1);
    const end_addr = dest_addr + ph.p_memsz;
    const end_page = (end_addr + page_size - 1) & ~(page_size - 1);

    var curr_page = start_page;
    while (curr_page < end_page) : (curr_page += page_size) {
        // 1. Allocate physical page
        const phys = pmm.allocatePage() orelse return ElfError.LoadFailed;

        // 2. Map page (RW for now, we should check ph.flags for RX/RW etc)
        // Always RWX for now since we are simple kernel
        try vmm.mapPage(curr_page, phys, vmm.PTE_PRESENT | vmm.PTE_RW, 0);
    }

    // 3. Copy Data
    if (ph.p_filesz > 0) {
        const dest = @as([*]u8, @ptrFromInt(dest_addr));
        const src = file_base + ph.p_offset;
        @memcpy(dest[0..ph.p_filesz], src[0..ph.p_filesz]);
    }

    // 4. Zero BSS (MemSz > FileSz)
    if (ph.p_memsz > ph.p_filesz) {
        const bss_start = dest_addr + ph.p_filesz;
        const bss_size = ph.p_memsz - ph.p_filesz;
        const bss_ptr = @as([*]u8, @ptrFromInt(bss_start));
        @memset(bss_ptr[0..bss_size], 0);
    }
}

// Local testing helper to avoid std.testing dependencies in freestanding
const testing = struct {
    fn expect(ok: bool) !void {
        if (!ok) return error.TestFailure;
    }

    fn expectError(expected: anyerror, actual: anyerror) !void {
        if (expected != actual) return error.TestFailure;
    }
};

test "ELF Header Validation" {
    // Construct a minimal valid ELF header
    var header = std.mem.zeroes(Elf64_Ehdr);
    @memcpy(header.e_ident[0..4], "\x7FELF");
    header.e_ident[std.elf.EI_CLASS] = std.elf.ELFCLASS64;
    header.e_ident[std.elf.EI_DATA] = std.elf.ELFDATA2LSB;
    header.e_ident[std.elf.EI_VERSION] = 1;
    header.e_machine = std.elf.EM.X86_64;
    header.e_version = 1;
    header.e_type = std.elf.ET.EXEC;
    header.e_ehsize = @sizeOf(Elf64_Ehdr);

    const ptr = @as([*]const u8, @ptrCast(&header));
    const size = @sizeOf(Elf64_Ehdr);

    // Should fail with load error or just pass validation up to parsing loop
    // Since ph_num is 0, it should just return e_entry (0)
    const entry = try loadElf(ptr, size);
    try testing.expect(entry == 0);
}

test "ELF Invalid Magic" {
    var header = std.mem.zeroes(Elf64_Ehdr);
    @memcpy(header.e_ident[0..4], "BAD!"); // Invalid magic

    const ptr = @as([*]const u8, @ptrCast(&header));
    const size = @sizeOf(Elf64_Ehdr);

    if (loadElf(ptr, size)) |_| {
        return error.TestFailure;
    } else |err| {
        try testing.expect(err == ElfError.InvalidMagic);
    }
}

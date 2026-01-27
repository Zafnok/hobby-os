const std = @import("std");

// GDT Descriptor (GDTR) - What we pass to 'lgdt'
const GdtDescriptor = packed struct {
    size: u16,
    offset: u64,
};

// GDT Entry - 64-bit Structure
const GdtEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

// Helper Struct to organize our GDT
const GlobalDescriptorTable = struct {
    entries: [3]GdtEntry, // Null, Kernel Code, Kernel Data

    pub fn init() GlobalDescriptorTable {
        return .{
            .entries = .{
                // 0: Null Descriptor
                GdtEntry{ .limit_low = 0, .base_low = 0, .base_middle = 0, .access = 0, .granularity = 0, .base_high = 0 },

                // 1: Kernel Code (Ring 0)
                // Access: Present(1) | Ring0(00) | Sys(1) | Exec(1) | Conforming(0) | Readable(1) | Accessed(0) -> 0x9A
                // Granularity: Granularity(1) | LongMode(1) | Size(0) | 0xF -> 0xAF
                GdtEntry{ .limit_low = 0xFFFF, .base_low = 0, .base_middle = 0, .access = 0x9A, .granularity = 0xAF, .base_high = 0 },

                // 2: Kernel Data (Ring 0)
                // Access: Present(1) | Ring0(00) | Sys(1) | Exec(0) | Direction(0) | Writable(1) | Accessed(0) -> 0x92
                // Granularity: Granularity(1) | LongMode(0) | Size(0) | 0xF -> 0xCF (LongMode ignored for data, but usually 0)
                GdtEntry{ .limit_low = 0xFFFF, .base_low = 0, .base_middle = 0, .access = 0x92, .granularity = 0xCF, .base_high = 0 },
            },
        };
    }

    pub fn load(self: *GlobalDescriptorTable) void {
        const descriptor = GdtDescriptor{
            .size = @sizeOf(@TypeOf(self.entries)) - 1,
            .offset = @intFromPtr(&self.entries),
        };

        asm volatile (
            \\ lgdt (%[gdtr])
            \\ mov $0x10, %%ax
            \\ mov %%ax, %%ds
            \\ mov %%ax, %%es
            \\ mov %%ax, %%fs
            \\ mov %%ax, %%gs
            \\ mov %%ax, %%ss
            \\ pushq $0x08
            \\ leaq  1f(%%rip), %%rax
            \\ pushq %%rax
            \\ lretq
            \\ 1:
            :
            : [gdtr] "r" (&descriptor),
            : .{ .rax = true, .memory = true });
    }
};

// Global Instance
var gdt: GlobalDescriptorTable = undefined;

pub fn init() void {
    gdt = GlobalDescriptorTable.init();
    gdt.load();
}

const std = @import("std");
const serial = @import("../../kernel/serial.zig");

// Interrupt Descriptor Table Pointer (IDTR)
const IdtDescriptor = packed struct {
    size: u16,
    offset: u64,
};

// IDT Entry - 128-bit Structure
const IdtEntry = packed struct {
    offset_low: u16,
    selector: u16,
    ist: u8,
    type_attr: u8,
    offset_middle: u16,
    offset_high: u32,
    zero: u32,

    pub fn init(offset: u64, selector: u16, type_attr: u8) IdtEntry {
        return .{
            .offset_low = @truncate(offset),
            .selector = selector,
            .ist = 0,
            .type_attr = type_attr,
            .offset_middle = @truncate(offset >> 16),
            .offset_high = @truncate(offset >> 32),
            .zero = 0,
        };
    }
};

// Interrupt Stack Frame (pushed by CPU + our assembly stub)
// Matches the push order in interrupts.S
pub const InterruptFrame = extern struct {
    // Saved by our assembly stub (isr_common_stub)
    rax: u64,
    rbx: u64,
    rcx: u64,
    rdx: u64,
    rsi: u64,
    rdi: u64,
    rbp: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,

    // Pushed by ISR stub macro
    int_num: u64,
    err_code: u64,

    // Pushed by CPU
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,
};

// The IDT itself
var idt_entries: [256]IdtEntry = undefined;

// Externs for Assembly Stubs
extern fn isr_stub_0() void;
extern fn isr_stub_1() void;
extern fn isr_stub_2() void;
extern fn isr_stub_3() void;
extern fn isr_stub_4() void;
extern fn isr_stub_5() void;
extern fn isr_stub_6() void;
extern fn isr_stub_7() void;
extern fn isr_stub_8() void;
extern fn isr_stub_9() void;
extern fn isr_stub_10() void;
extern fn isr_stub_11() void;
extern fn isr_stub_12() void;
extern fn isr_stub_13() void;
extern fn isr_stub_14() void;
extern fn isr_stub_15() void;
extern fn isr_stub_16() void;
extern fn isr_stub_17() void;
extern fn isr_stub_18() void;
extern fn isr_stub_19() void;
extern fn isr_stub_20() void;
extern fn isr_stub_21() void;
extern fn isr_stub_22() void;
extern fn isr_stub_23() void;
extern fn isr_stub_24() void;
extern fn isr_stub_25() void;
extern fn isr_stub_26() void;
extern fn isr_stub_27() void;
extern fn isr_stub_28() void;
extern fn isr_stub_29() void;
extern fn isr_stub_30() void;
extern fn isr_stub_31() void;

// Helper to get function address
fn getAddr(func: *const fn () callconv(.c) void) u64 {
    return @intFromPtr(func);
}

pub fn init() void {
    // 0x8E = Present(1) | Ring0(00) | Gate(0) | InterruptGate(1110)
    const kernel_code_selector = 0x08; // Offset of Kernel Code in GDT
    const idt_attr = 0x8E;

    // Zero out database
    // @memset(&idt_entries, std.mem.zeroes(IdtEntry)); // Usually necessary, but undefined is fine if we set all used ones. Better to be safe?
    // Let's just set the ones we use.

    idt_entries[0] = IdtEntry.init(getAddr(isr_stub_0), kernel_code_selector, idt_attr);
    idt_entries[1] = IdtEntry.init(getAddr(isr_stub_1), kernel_code_selector, idt_attr);
    idt_entries[2] = IdtEntry.init(getAddr(isr_stub_2), kernel_code_selector, idt_attr);
    idt_entries[3] = IdtEntry.init(getAddr(isr_stub_3), kernel_code_selector, idt_attr);
    idt_entries[4] = IdtEntry.init(getAddr(isr_stub_4), kernel_code_selector, idt_attr);
    idt_entries[5] = IdtEntry.init(getAddr(isr_stub_5), kernel_code_selector, idt_attr);
    idt_entries[6] = IdtEntry.init(getAddr(isr_stub_6), kernel_code_selector, idt_attr);
    idt_entries[7] = IdtEntry.init(getAddr(isr_stub_7), kernel_code_selector, idt_attr);
    idt_entries[8] = IdtEntry.init(getAddr(isr_stub_8), kernel_code_selector, idt_attr);
    idt_entries[9] = IdtEntry.init(getAddr(isr_stub_9), kernel_code_selector, idt_attr);
    idt_entries[10] = IdtEntry.init(getAddr(isr_stub_10), kernel_code_selector, idt_attr);
    idt_entries[11] = IdtEntry.init(getAddr(isr_stub_11), kernel_code_selector, idt_attr);
    idt_entries[12] = IdtEntry.init(getAddr(isr_stub_12), kernel_code_selector, idt_attr);
    idt_entries[13] = IdtEntry.init(getAddr(isr_stub_13), kernel_code_selector, idt_attr);
    idt_entries[14] = IdtEntry.init(getAddr(isr_stub_14), kernel_code_selector, idt_attr);
    idt_entries[15] = IdtEntry.init(getAddr(isr_stub_15), kernel_code_selector, idt_attr);
    idt_entries[16] = IdtEntry.init(getAddr(isr_stub_16), kernel_code_selector, idt_attr);
    idt_entries[17] = IdtEntry.init(getAddr(isr_stub_17), kernel_code_selector, idt_attr);
    idt_entries[18] = IdtEntry.init(getAddr(isr_stub_18), kernel_code_selector, idt_attr);
    idt_entries[19] = IdtEntry.init(getAddr(isr_stub_19), kernel_code_selector, idt_attr);
    idt_entries[20] = IdtEntry.init(getAddr(isr_stub_20), kernel_code_selector, idt_attr);
    idt_entries[21] = IdtEntry.init(getAddr(isr_stub_21), kernel_code_selector, idt_attr);
    idt_entries[22] = IdtEntry.init(getAddr(isr_stub_22), kernel_code_selector, idt_attr);
    idt_entries[23] = IdtEntry.init(getAddr(isr_stub_23), kernel_code_selector, idt_attr);
    idt_entries[24] = IdtEntry.init(getAddr(isr_stub_24), kernel_code_selector, idt_attr);
    idt_entries[25] = IdtEntry.init(getAddr(isr_stub_25), kernel_code_selector, idt_attr);
    idt_entries[26] = IdtEntry.init(getAddr(isr_stub_26), kernel_code_selector, idt_attr);
    idt_entries[27] = IdtEntry.init(getAddr(isr_stub_27), kernel_code_selector, idt_attr);
    idt_entries[28] = IdtEntry.init(getAddr(isr_stub_28), kernel_code_selector, idt_attr);
    idt_entries[29] = IdtEntry.init(getAddr(isr_stub_29), kernel_code_selector, idt_attr);
    idt_entries[30] = IdtEntry.init(getAddr(isr_stub_30), kernel_code_selector, idt_attr);
    idt_entries[31] = IdtEntry.init(getAddr(isr_stub_31), kernel_code_selector, idt_attr);

    load();
}

fn load() void {
    const descriptor = IdtDescriptor{
        .size = @sizeOf(@TypeOf(idt_entries)) - 1,
        .offset = @intFromPtr(&idt_entries),
    };

    asm volatile (
        \\ lidt (%[idtr])
        :
        : [idtr] "r" (&descriptor),
    );
}

// Global Exception Handler called from ASM
export fn handleInterrupt(frame: *InterruptFrame) callconv(.c) void {
    serial.err("------------------------------------------------");
    serial.err("EXCEPTION CAUGHT");
    serial.err("------------------------------------------------");

    serial.err("Interrupt Number:");
    serial.printHex(.error_level, frame.int_num);
    serial.err("Error Code:");
    serial.printHex(.error_level, frame.err_code);
    serial.err("RIP:");
    serial.printHex(.error_level, frame.rip);
    serial.err("CS:");
    serial.printHex(.error_level, frame.cs);
    serial.err("RFLAGS:");
    serial.printHex(.error_level, frame.rflags);
    serial.err("RSP:");
    serial.printHex(.error_level, frame.rsp);

    // Page Fault specific info
    if (frame.int_num == 14) {
        const cr2 = asm volatile ("mov %%cr2, %[ret]"
            : [ret] "=r" (-> u64),
        );
        serial.err("CR2 (Fault Address):");
        serial.printHex(.error_level, cr2);
    }

    serial.err("System Halted.");
    while (true) {
        asm volatile ("hlt");
    }
}

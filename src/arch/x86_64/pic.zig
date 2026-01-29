const io = @import("io.zig");

// PIC Ports
const PIC1_COMMAND = 0x20;
const PIC1_DATA = 0x21;
const PIC2_COMMAND = 0xA0;
const PIC2_DATA = 0xA1;

// Initialization Command Words
const ICW1_INIT = 0x10;
const ICW1_ICW4 = 0x01;
const ICW4_8086 = 0x01;

// Remapping Offsets
const PIC1_OFFSET = 0x20; // Vectors 32-39
const PIC2_OFFSET = 0x28; // Vectors 40-47

pub fn init() void {
    // Save masks (discarded for now as we mask all at the end)
    _ = io.inb(PIC1_DATA);
    _ = io.inb(PIC2_DATA);

    // ICW1: Init
    io.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    io.wait();
    io.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    io.wait();

    // ICW2: Vector Offsets
    io.outb(PIC1_DATA, PIC1_OFFSET);
    io.wait();
    io.outb(PIC2_DATA, PIC2_OFFSET);
    io.wait();

    // ICW3: Cascade setup
    io.outb(PIC1_DATA, 4); // Tell Master there is Slave at IRQ2 (0000 0100)
    io.wait();
    io.outb(PIC2_DATA, 2); // Tell Slave its cascade identity (0000 0010)
    io.wait();

    // ICW4: 8086 Mode
    io.outb(PIC1_DATA, ICW4_8086);
    io.wait();
    io.outb(PIC2_DATA, ICW4_8086);
    io.wait();

    // Restore masks (or mask all?)
    // For now, let's Mask ALL to prevent spurious interrupts until we register handlers.
    // NOTE: The user's original goal implies we want to enable Keyboard (IRQ1) later.
    // So masking all is safe default.
    io.outb(PIC1_DATA, 0xFF);
    io.outb(PIC2_DATA, 0xFF);
}

/// Send End of Interrupt to PIC.
/// Must be called at end of ISR for IRQs.
pub fn sendEoi(irq: u8) void {
    if (irq >= 8) {
        io.outb(PIC2_COMMAND, 0x20);
    }
    io.outb(PIC1_COMMAND, 0x20);
}

/// Unmasks a specific IRQ line.
pub fn unmaskIrq(irq: u8) void {
    var port: u16 = PIC1_DATA;
    var line = irq;

    if (irq >= 8) {
        port = PIC2_DATA;
        line -= 8;
    }

    const value = io.inb(port) & ~(@as(u8, 1) << @intCast(line));
    io.outb(port, value);
}

/// Masks a specific IRQ line.
pub fn maskIrq(irq: u8) void {
    var port: u16 = PIC1_DATA;
    var line = irq;

    if (irq >= 8) {
        port = PIC2_DATA;
        line -= 8;
    }

    const value = io.inb(port) | (@as(u8, 1) << @intCast(line));
    io.outb(port, value);
}

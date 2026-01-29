const io = @import("../arch/x86_64/io.zig");
const serial = @import("../kernel/serial.zig");
const pic = @import("../arch/x86_64/pic.zig");

// Circular Buffer
const BUFFER_SIZE = 256;
var buffer: [BUFFER_SIZE]u8 = undefined;
var write_idx: usize = 0;
var read_idx: usize = 0;

// Scancode Table (Set 1) - minimal (no shift support yet)
// 0 = Unknown/Special
const scancode_map = [_]u8{
    0,   27,  '1', '2', '3', '4', '5', '6', '7',  '8', '9', '0',  '-', '=', 8,   9,
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o',  'p', '[', ']',  10,  0,   'a', 's',
    'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0,   '\\', 'z', 'x', 'c', 'v',
    'b', 'n', 'm', ',', '.', '/', 0,   '*', 0,    ' ',
    0,
    // ... F-keys usually follow
};

pub fn init() void {
    // Unmask IRQ1 (Keyboard)
    pic.unmaskIrq(1);
    serial.info("Keyboard Initialized (IRQ1 Unmasked)");
}

pub fn handleIrq() void {
    const scancode = io.inb(0x60);
    serial.debug("Keyboard IRQ! Scancode: ");
    serial.printHex(.debug, scancode);

    // Ignore Break codes (highest bit set) for now
    if (scancode & 0x80 != 0) {
        return;
    }

    if (scancode < scancode_map.len) {
        const char = scancode_map[scancode];
        if (char != 0) {
            push(char);
            serial.debug("Key Pressed: ");
            serial.printHex(.debug, char);
        }
    }
}

fn push(c: u8) void {
    // If buffer full, drop? Or overwrite? Let's drop.
    const next_write = (write_idx + 1) % BUFFER_SIZE;
    if (next_write == read_idx) {
        serial.warn("Keyboard Buffer Full!");
        return;
    }
    buffer[write_idx] = c;
    write_idx = next_write;
}

pub fn pop() ?u8 {
    // Atomic load of write_idx effectively needed, but on single core x64,
    // aligned size_t access is atomic.
    if (read_idx == getWriteIdx()) {
        return null;
    }
    const c = buffer[read_idx];
    read_idx = (read_idx + 1) % BUFFER_SIZE;
    return c;
}

// Helper to ensure we read the latest write_idx (prevent optimization caching)
fn getWriteIdx() usize {
    const ptr = @as(*volatile usize, &write_idx);
    return ptr.*;
}

test "Keyboard Buffer Logic" {
    // std.testing pulls in logic not supported in freestanding.
    // Use manual checks.

    // Reset state for test
    write_idx = 0;
    read_idx = 0;

    push('A');
    push('B');
    push('C');

    if (pop() != 'A') return error.TestFailed;
    if (pop() != 'B') return error.TestFailed;
    if (pop() != 'C') return error.TestFailed;
    if (pop() != null) return error.TestFailed;
}

const io = @import("../arch/x86_64/io.zig");
const serial = @import("../kernel/serial.zig");
const apic = @import("../arch/x86_64/apic.zig");

// Circular Buffer
const BUFFER_SIZE = 256;
var buffer: [BUFFER_SIZE]u8 = undefined;
var write_idx: usize = 0;
var read_idx: usize = 0;

// Scancode Table (Set 1)
// 0 = Unknown/Special
const scancode_map = [_]u8{
    0,   27,  '1', '2', '3', '4', '5', '6', '7',  '8', '9', '0',  '-', '=', 8,   9,
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o',  'p', '[', ']',  10,  0,   'a', 's',
    'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0,   '\\', 'z', 'x', 'c', 'v',
    'b', 'n', 'm', ',', '.', '/', 0,   '*', 0,    ' ', 0,
};

const scancode_shift_map = [_]u8{
    0,   27,  '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 8,   9,
    'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 10,  0,   'A', 'S',
    'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0,   '|', 'Z', 'X', 'C', 'V',
    'B', 'N', 'M', '<', '>', '?', 0,   '*', 0,   ' ', 0,
};

var shift_pressed: bool = false;

/// Flushes any stale data from the keyboard controller's output buffer.
/// This prevents early key presses (before initialization) from leaving the controller in a faulty state.
fn flushBuffer() void {
    var flushed_count: usize = 0;
    const max_iterations: usize = 100; // Prevent infinite loop
    var iterations: usize = 0;

    while (iterations < max_iterations) : (iterations += 1) {
        // Read keyboard controller status register (port 0x64)
        // Bit 0: Output buffer status (1 = full, 0 = empty)
        const status = io.inb(0x64);

        if (status & 0x01 == 0) {
            // Output buffer is empty, we're done
            break;
        }

        // Read and discard the byte from the data port
        _ = io.inb(0x60);
        flushed_count += 1;
    }

    if (flushed_count > 0) {
        serial.info("Keyboard: Flushed stale bytes from buffer:");
        serial.printHex(.info, flushed_count);
    }
}

pub fn init() void {
    // Flush any stale data from early key presses before enabling interrupts
    flushBuffer();

    // Unmask IRQ1 (Keyboard) -> Map to Vector 33
    // IOAPIC Redirection
    apic.enableIrq(1, 33);
    serial.info("Keyboard Initialized (APIC IRQ1 -> Vec 33)");
}

pub fn handleIrq() void {
    const scancode = io.inb(0x60);

    // Ignore Break codes for normal keys, but catch Shift release
    if (scancode & 0x80 != 0) {
        // Break code (Key Release)
        const key_released = scancode & 0x7F;
        if (key_released == 0x2A or key_released == 0x36) {
            shift_pressed = false;
        }
        return;
    }

    // Make code (Key Press)
    if (scancode == 0x2A or scancode == 0x36) {
        shift_pressed = true;
        return;
    }

    if (scancode < scancode_map.len) {
        var char: u8 = 0;
        if (shift_pressed) {
            char = scancode_shift_map[scancode];
        } else {
            char = scancode_map[scancode];
        }

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

test "Keyboard Buffer Flush" {
    // Test that flushBuffer doesn't crash and handles empty buffer gracefully
    // Note: In test environment, we can't actually read from port 0x60/0x64,
    // but we can verify the function is callable and doesn't panic.
    // In actual hardware/QEMU, this will read the real status register.

    // This test verifies the function signature and basic control flow.
    // The actual hardware interaction is tested during manual QEMU runs.
    flushBuffer();

    // If we get here without panicking, the test passes
}

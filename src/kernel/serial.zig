const io = @import("../arch/x86_64/io.zig");
const build_options = @import("build_options");

pub const LogLevel = enum {
    debug,
    info,
    warn,
    error_level, // avoiding keyword 'error'
};

// Map build_options enum to our enum (names match, mostly)
// We need to ensure we compare values correctly.
// build_options.LogLevel is a separate type from this one.
// We can assume numerical order: debug=0, info=1, warn=2, error=3.

/// Determines if the message should be logged based on the configured log level.
fn shouldLog(level: LogLevel) bool {
    // Basic enum to int conversion for comparison
    const min_level_int = @intFromEnum(build_options.log_level);
    const msg_level_int = @intFromEnum(level);
    return msg_level_int >= min_level_int;
}

/// Logs a message with the specified log level if it meets the configured verbosity.
/// Prepends a tag (e.g., "[INFO]") to the message.
pub fn log(comptime level: LogLevel, msg: []const u8) void {
    if (comptime shouldLog(level)) {
        // Prepend tag
        const tag = switch (level) {
            .debug => "[DEBUG] ",
            .info => "[INFO] ",
            .warn => "[WARN] ",
            .error_level => "[ERROR] ",
        };
        for (tag) |c| {
            io.outb(0x3F8, c);
        }
        logRaw(msg);
        io.outb(0x3F8, '\n');
    }
}

/// Logs a debug message.
pub fn debug(msg: []const u8) void {
    log(.debug, msg);
}

/// Logs an info message.
pub fn info(msg: []const u8) void {
    log(.info, msg);
}

/// Logs a warning message.
pub fn warn(msg: []const u8) void {
    log(.warn, msg);
}

/// Logs an error message.
pub fn err(msg: []const u8) void {
    log(.error_level, msg);
}

/// Logs raw bytes to the serial port without any prefix or newline.
/// This is intended for userspace use via the Kernel Table where userspace
/// controls all formatting and output (e.g., for game scores, progress bars, etc.).
///
/// Example:
///   logRaw("Score: ");  // No newline
///   logRaw("42");       // Outputs "Score: 42" on same line
pub fn logRaw(msg: []const u8) void {
    for (msg) |c| {
        io.outb(0x3F8, c);
    }
}

/// Prints a 64-bit unsigned integer in hexadecimal format to the serial port.
pub fn printHex(comptime level: LogLevel, value: u64) void {
    if (comptime shouldLog(level)) {
        const digits = "0123456789ABCDEF";
        for ("0x") |c| {
            io.outb(0x3F8, c);
        }
        var shift: u6 = 60;
        while (true) {
            const digit_index = (value >> shift) & 0xF;
            io.outb(0x3F8, digits[digit_index]);
            if (shift == 0) break;
            shift -= 4;
        }
        io.outb(0x3F8, '\n');
    }
}

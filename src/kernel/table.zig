/// Kernel Table - Userspace Function Pointer Interface
///
/// This module defines the contract between kernel and userspace in our SASOS architecture.
/// Instead of using syscalls, userspace programs receive a pointer to a KernelTable struct
/// at startup, which contains function pointers to kernel services.
///
/// This approach leverages our Single Address Space Operating System (SASOS) design where
/// kernel and userspace share the same address space but are isolated via PKS (Protection Keys).
const std = @import("std");

/// Magic number used to validate the KernelTable struct.
/// If userspace reads a different magic value, the kernel table is corrupted or invalid.
pub const KERNEL_TABLE_MAGIC: u64 = 0xDEADC0DE;

/// The kernel-userspace function pointer table.
///
/// This struct uses `extern` layout to ensure a stable C-compatible ABI.
/// All function pointers use C calling convention for compatibility with userspace programs
/// that may be written in any language (Zig, C, Assembly, etc.).
///
/// The kernel populates this table with function pointers to kernel services,
/// and the ELF loader passes a pointer to this table to userspace programs at startup.
pub const KernelTable = extern struct {
    /// Magic number for validation. Should always be KERNEL_TABLE_MAGIC (0xDEADC0DE).
    magic: u64,

    /// Logs a message to the serial console (COM1).
    ///
    /// Parameters:
    ///   - ptr: Pointer to the start of the message string
    ///   - len: Length of the message in bytes
    ///
    /// The message is not required to be null-terminated.
    /// This function does not block and is safe to call from any context.
    log: *const fn (ptr: [*]const u8, len: usize) callconv(.c) void,

    /// Draws a filled rectangle on the framebuffer.
    ///
    /// Parameters:
    ///   - x: X coordinate of the top-left corner (pixels)
    ///   - y: Y coordinate of the top-left corner (pixels)
    ///   - w: Width of the rectangle (pixels)
    ///   - h: Height of the rectangle (pixels)
    ///   - color: Color in 0xAARRGGBB format (32-bit ARGB)
    ///
    /// Coordinates that fall outside the framebuffer bounds are clipped.
    /// This function does not block.
    draw_rect: *const fn (x: u32, y: u32, w: u32, h: u32, color: u32) callconv(.c) void,

    /// Polls for keyboard input (non-blocking).
    ///
    /// Returns:
    ///   - The ASCII character code if a key is available
    ///   - 0 if no key is currently pressed or in the buffer
    ///
    /// This function never blocks. It returns immediately with either a character
    /// or 0 if no input is available. Userspace should poll this repeatedly in a
    /// game loop or input handling routine.
    poll_key: *const fn () callconv(.c) u8,

    /// Delays execution for the specified number of milliseconds.
    ///
    /// Parameters:
    ///   - ms: Number of milliseconds to sleep
    ///
    /// NOTE: Current implementation is a busy-wait loop. This will be replaced
    /// with a proper timer-based sleep once we have APIC timer support.
    /// Do not use this for long delays as it will consume CPU cycles.
    sleep_ms: *const fn (ms: u64) callconv(.c) void,

    /// Allocates contiguous physical memory pages.
    ///
    /// Parameters:
    ///   - count: Number of pages to allocate (each page is 4KB)
    ///
    /// Returns:
    ///   - Pointer to the start of the allocated memory region on success
    ///   - null if allocation fails (out of memory)
    ///
    /// The returned memory is guaranteed to be physically contiguous.
    /// Memory is not zeroed by default.
    /// Userspace is responsible for freeing allocated pages when done.
    alloc_pages: *const fn (count: usize) callconv(.c) ?[*]u8,
};

// ============================================================================
// Unit Tests
// ============================================================================

test "KernelTable Layout Validation" {
    // Verify the struct has the expected size and layout.
    // This ensures compatibility when passing between kernel and userspace.
    const table_size = @sizeOf(KernelTable);

    // Expected size calculation:
    // - magic: 8 bytes (u64)
    // - log: 8 bytes (function pointer)
    // - draw_rect: 8 bytes (function pointer)
    // - poll_key: 8 bytes (function pointer)
    // - sleep_ms: 8 bytes (function pointer)
    // - alloc_pages: 8 bytes (function pointer)
    // Total: 48 bytes
    try std.testing.expect(table_size == 48);
}

test "KernelTable Magic Constant" {
    // Verify the magic constant has the expected value
    try std.testing.expect(KERNEL_TABLE_MAGIC == 0xDEADC0DE);
}

test "KernelTable Field Offsets" {
    // Verify field offsets are as expected for C ABI compatibility
    try std.testing.expect(@offsetOf(KernelTable, "magic") == 0);
    try std.testing.expect(@offsetOf(KernelTable, "log") == 8);
    try std.testing.expect(@offsetOf(KernelTable, "draw_rect") == 16);
    try std.testing.expect(@offsetOf(KernelTable, "poll_key") == 24);
    try std.testing.expect(@offsetOf(KernelTable, "sleep_ms") == 32);
    try std.testing.expect(@offsetOf(KernelTable, "alloc_pages") == 40);
}

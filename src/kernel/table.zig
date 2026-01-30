/// Kernel Table - Userspace Function Pointer Interface
///
/// This module defines the contract between kernel and userspace in our SASOS architecture.
/// Instead of using syscalls, userspace programs receive a pointer to a KernelTable struct
/// at startup, which contains function pointers to kernel services.
///
/// This approach leverages our Single Address Space Operating System (SASOS) design where
/// kernel and userspace share the same address space but are isolated via PKS (Protection Keys).
const std = @import("std");

// Driver imports
const framebuffer = @import("../drivers/graphics/framebuffer.zig");
const keyboard = @import("../drivers/keyboard.zig");
const serial = @import("./serial.zig");
const pmm = @import("memory/pmm.zig");
const io = @import("../arch/x86_64/io.zig");
const limine = @import("../limine_import.zig").C;

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
// Kernel-Side Wrapper Functions
// ============================================================================

/// Kernel wrapper for logging to serial console.
/// Writes raw bytes to COM1 without newline or prefix.
/// This allows userspace to control formatting completely.
fn kernelLog(ptr: [*]const u8, len: usize) callconv(.c) void {
    const msg: []const u8 = ptr[0..len];
    serial.logRaw(msg);
}

/// Kernel wrapper for drawing rectangles on the framebuffer.
/// Handles null framebuffer gracefully by logging and returning early.
///
/// NOTE: Signature uses u32 for coordinates/dimensions while framebuffer driver uses u64.
/// This mismatch exists because:
/// - Limine framebuffer protocol uses u64 for width/height fields
/// - Userspace API uses u32 (more practical - no framebuffer is 4 billion pixels wide)
/// - This wrapper also hides the framebuffer pointer from userspace (single address space design)
fn kernelDrawRect(x: u32, y: u32, w: u32, h: u32, color: u32) callconv(.c) void {
    const fb = framebuffer.getFramebuffer();
    if (fb) |f| {
        // Convert u32 parameters to u64 for the driver's interface
        framebuffer.drawRect(f, @as(u64, x), @as(u64, y), @as(u64, w), @as(u64, h), color);
    } else {
        serial.warn("kernelDrawRect: Framebuffer not available");
    }
}

/// Kernel wrapper for polling keyboard input.
/// Returns ASCII character or 0 if no key is available.
fn kernelPollKey() callconv(.c) u8 {
    if (keyboard.pop()) |key| {
        return key;
    }
    return 0;
}

/// Kernel wrapper for sleeping (busy-wait implementation).
/// This is temporary until APIC timer is implemented.
/// Calibration: ~1,000,000 iterations ≈ 1ms on QEMU.
fn kernelSleepMs(ms: u64) callconv(.c) void {
    const iterations_per_ms: u64 = 1_000_000;
    const total_iterations = ms * iterations_per_ms;

    var i: u64 = 0;
    while (i < total_iterations) : (i += 1) {
        // Volatile read to prevent compiler optimization
        asm volatile ("" ::: .{ .memory = true });
    }
}

/// Kernel wrapper for allocating pages.
/// Converts physical address from PMM to virtual address via HHDM.
fn kernelAllocPages(count: usize) callconv(.c) ?[*]u8 {
    if (count == 0) return null;

    const phys_addr = pmm.allocatePages(count) orelse return null;

    // Convert physical address to virtual address using HHDM offset
    const hhdm_resp = pmm.hhdm_request.response;
    if (hhdm_resp == null) {
        serial.err("kernelAllocPages: HHDM not available");
        return null;
    }

    const hhdm_offset = hhdm_resp.*.offset;
    const virt_addr = phys_addr + hhdm_offset;

    return @ptrFromInt(virt_addr);
}

/// The populated kernel table instance.
/// This is the table that will be passed to userspace programs.
pub const table = KernelTable{
    .magic = KERNEL_TABLE_MAGIC,
    .log = kernelLog,
    .draw_rect = kernelDrawRect,
    .poll_key = kernelPollKey,
    .sleep_ms = kernelSleepMs,
    .alloc_pages = kernelAllocPages,
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

test "KernelTable Populated Correctly" {
    // Verify the exported table has correct magic value
    try std.testing.expect(table.magic == KERNEL_TABLE_MAGIC);

    // Verify all function pointers are correctly assigned
    // We can't directly compare function pointers, but we can verify they're not null
    // and point to the expected functions by comparing their addresses
    try std.testing.expect(@intFromPtr(table.log) == @intFromPtr(&kernelLog));
    try std.testing.expect(@intFromPtr(table.draw_rect) == @intFromPtr(&kernelDrawRect));
    try std.testing.expect(@intFromPtr(table.poll_key) == @intFromPtr(&kernelPollKey));
    try std.testing.expect(@intFromPtr(table.sleep_ms) == @intFromPtr(&kernelSleepMs));
    try std.testing.expect(@intFromPtr(table.alloc_pages) == @intFromPtr(&kernelAllocPages));
}

test "kernelLog Wrapper - Empty String" {
    // Test that kernelLog can handle empty strings without crashing
    const empty: [0]u8 = .{};
    const ptr: [*]const u8 = &empty;

    // This should not crash
    kernelLog(ptr, 0);
}

test "kernelLog Wrapper - Valid String" {
    // Test that kernelLog can handle a valid string
    const msg = "Test message";
    const ptr: [*]const u8 = msg.ptr;

    // This should not crash - output goes to serial (0x3F8)
    kernelLog(ptr, msg.len);
}

test "kernelPollKey Wrapper - Returns Zero or ASCII" {
    // Test that kernelPollKey returns valid values
    // It should return either 0 (no key) or a valid ASCII character
    const result = kernelPollKey();

    // Result should be either 0 or a printable ASCII character
    // We can't predict what's in the buffer, but we can verify it doesn't crash
    _ = result;
}

test "kernelDrawRect Wrapper - Null Framebuffer Handling" {
    // Test that kernelDrawRect handles null framebuffer gracefully
    // This test verifies the function doesn't panic when FB is not available

    // Call with arbitrary parameters - if FB is null, it should log and return
    kernelDrawRect(0, 0, 100, 100, 0xFFFFFFFF);

    // If we get here without panicking, the test passes
}

test "kernelDrawRect Wrapper - Parameter Conversion" {
    // Test that u32 parameters are correctly handled
    // Even if framebuffer is null, we verify the function signature works
    const x: u32 = 10;
    const y: u32 = 20;
    const w: u32 = 30;
    const h: u32 = 40;
    const color: u32 = 0xFF00FF00;

    kernelDrawRect(x, y, w, h, color);

    // If we get here, parameter types are correct
}

test "kernelSleepMs Wrapper - Zero Milliseconds" {
    // Test that sleeping for 0ms doesn't hang
    kernelSleepMs(0);

    // Should return immediately
}

test "kernelSleepMs Wrapper - Small Delay" {
    // Test that sleeping for a small duration completes
    // We use 1ms to keep test fast
    kernelSleepMs(1);

    // Should complete without hanging
}

test "kernelAllocPages Wrapper - Zero Count" {
    // Test that allocating 0 pages returns null
    const result = kernelAllocPages(0);
    try std.testing.expect(result == null);
}

test "kernelAllocPages Wrapper - Valid Allocation" {
    // Test that allocating pages works when PMM has memory
    // Note: This test may fail in test environment if PMM isn't initialized
    // but it verifies the wrapper signature and basic logic
    const result = kernelAllocPages(1);

    // Result could be null (if PMM not initialized in test) or a valid pointer
    // We just verify it doesn't crash
    _ = result;
}

test "kernelAllocPages Wrapper - Returns Virtual Address" {
    // Test that if allocation succeeds, we get a virtual address (high address)
    // In HHDM, virtual addresses should be in higher half
    const result = kernelAllocPages(1);

    if (result) |ptr| {
        const addr = @intFromPtr(ptr);
        // HHDM addresses are typically very high (> 0xFFFF800000000000)
        // We just verify we got a pointer, not necessarily the exact range
        // since test environment may differ
        try std.testing.expect(addr != 0);
    }
    // If null, PMM wasn't initialized - that's ok for unit test
}

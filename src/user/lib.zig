/// User Runtime Library - Idiomatic Zig Wrappers for Kernel Table
///
/// This module provides a clean Zig interface for userspace programs to interact
/// with kernel services via the kernel table function pointer interface.
///
/// The kernel table is passed to userspace at program startup and stored here.
/// All wrapper functions convert from C ABI (function pointers, raw values) to
/// idiomatic Zig types (slices, optionals, etc.).
const table_def = @import("../kernel/table.zig");
const KernelTable = table_def.KernelTable;

/// Global kernel table pointer, initialized at program startup.
/// This is set by the _start function in start.zig before calling main().
var kernel_table: ?*const KernelTable = null;

/// Initialize the user runtime library with the kernel table.
/// This MUST be called by _start before any other user runtime functions are used.
///
/// Parameters:
///   - table: Pointer to the kernel table passed by the ELF loader
pub fn init(table: *const KernelTable) void {
    kernel_table = table;
}

/// Draw a filled rectangle on the framebuffer.
///
/// Parameters:
///   - x: X coordinate of the top-left corner (pixels)
///   - y: Y coordinate of the top-left corner (pixels)
///   - w: Width of the rectangle (pixels)
///   - h: Height of the rectangle (pixels)
///   - color: Color in 0xAARRGGBB format (32-bit ARGB)
///
/// Panics if the kernel table has not been initialized via init().
pub fn drawRect(x: u32, y: u32, w: u32, h: u32, color: u32) void {
    const table = kernel_table orelse @panic("User runtime not initialized - call lib.init() first");
    table.draw_rect(x, y, w, h, color);
}

/// Poll for keyboard input (non-blocking).
///
/// Returns:
///   - Some(char) if a key is available
///   - null if no key is currently pressed or in the buffer
///
/// This function never blocks. Use in a loop to continuously check for input.
///
/// Panics if the kernel table has not been initialized via init().
pub fn getKey() ?u8 {
    const table = kernel_table orelse @panic("User runtime not initialized - call lib.init() first");
    const result = table.poll_key();
    if (result == 0) {
        return null;
    }
    return result;
}

/// Sleep for the specified number of milliseconds.
///
/// Parameters:
///   - ms: Number of milliseconds to sleep
///
/// NOTE: Current implementation is a busy-wait loop.
/// Do not use for long delays as it will consume CPU cycles.
///
/// Panics if the kernel table has not been initialized via init().
pub fn sleep(ms: u64) void {
    const table = kernel_table orelse @panic("User runtime not initialized - call lib.init() first");
    table.sleep_ms(ms);
}

/// Log a message to the serial console.
///
/// Parameters:
///   - msg: Message string to log
///
/// The message is written to the serial console (COM1) without any prefix or newline.
/// Use this for debugging output, game state logging, etc.
///
/// Panics if the kernel table has not been initialized via init().
pub fn log(msg: []const u8) void {
    const table = kernel_table orelse @panic("User runtime not initialized - call lib.init() first");
    table.log(msg.ptr, msg.len);
}

/// Allocate contiguous physical memory pages.
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
///
/// Panics if the kernel table has not been initialized via init().
pub fn allocPages(count: usize) ?[*]u8 {
    const table = kernel_table orelse @panic("User runtime not initialized - call lib.init() first");
    return table.alloc_pages(count);
}

// ============================================================================
// Unit Tests
// ============================================================================

const std = @import("std");

test "User Runtime - Initialization" {
    // Create a mock kernel table for testing
    const mock_table = KernelTable{
        .magic = table_def.KERNEL_TABLE_MAGIC,
        .log = struct {
            fn mockLog(_: [*]const u8, _: usize) callconv(.c) void {}
        }.mockLog,
        .draw_rect = struct {
            fn mockDrawRect(_: u32, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}
        }.mockDrawRect,
        .poll_key = struct {
            fn mockPollKey() callconv(.c) u8 {
                return 0;
            }
        }.mockPollKey,
        .sleep_ms = struct {
            fn mockSleep(_: u64) callconv(.c) void {}
        }.mockSleep,
        .alloc_pages = struct {
            fn mockAllocPages(_: usize) callconv(.c) ?[*]u8 {
                return null;
            }
        }.mockAllocPages,
    };

    // Initialize with mock table
    init(&mock_table);

    // Verify table is set
    try std.testing.expect(kernel_table != null);
    try std.testing.expect(kernel_table.?.magic == table_def.KERNEL_TABLE_MAGIC);
}

test "User Runtime - getKey Wrapper Converts 0 to null" {
    // Setup mock that returns 0 (no key)
    const mock_table = KernelTable{
        .magic = table_def.KERNEL_TABLE_MAGIC,
        .log = struct {
            fn mockLog(_: [*]const u8, _: usize) callconv(.c) void {}
        }.mockLog,
        .draw_rect = struct {
            fn mockDrawRect(_: u32, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}
        }.mockDrawRect,
        .poll_key = struct {
            fn mockPollKey() callconv(.c) u8 {
                return 0;
            }
        }.mockPollKey,
        .sleep_ms = struct {
            fn mockSleep(_: u64) callconv(.c) void {}
        }.mockSleep,
        .alloc_pages = struct {
            fn mockAllocPages(_: usize) callconv(.c) ?[*]u8 {
                return null;
            }
        }.mockAllocPages,
    };

    init(&mock_table);
    const result = getKey();
    try std.testing.expect(result == null);
}

test "User Runtime - getKey Wrapper Returns Character" {
    // Setup mock that returns ASCII 'A'
    const mock_table = KernelTable{
        .magic = table_def.KERNEL_TABLE_MAGIC,
        .log = struct {
            fn mockLog(_: [*]const u8, _: usize) callconv(.c) void {}
        }.mockLog,
        .draw_rect = struct {
            fn mockDrawRect(_: u32, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}
        }.mockDrawRect,
        .poll_key = struct {
            fn mockPollKey() callconv(.c) u8 {
                return 'A';
            }
        }.mockPollKey,
        .sleep_ms = struct {
            fn mockSleep(_: u64) callconv(.c) void {}
        }.mockSleep,
        .alloc_pages = struct {
            fn mockAllocPages(_: usize) callconv(.c) ?[*]u8 {
                return null;
            }
        }.mockAllocPages,
    };

    init(&mock_table);
    const result = getKey();
    try std.testing.expect(result != null);
    try std.testing.expect(result.? == 'A');
}

test "User Runtime - log Wrapper Converts Slice to Pointer+Length" {
    // Track that log was called with correct parameters
    const TestState = struct {
        var called: bool = false;
        var length: usize = 0;

        fn mockLog(_: [*]const u8, len: usize) callconv(.c) void {
            called = true;
            length = len;
        }
    };

    const mock_table = KernelTable{
        .magic = table_def.KERNEL_TABLE_MAGIC,
        .log = TestState.mockLog,
        .draw_rect = struct {
            fn mockDrawRect(_: u32, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}
        }.mockDrawRect,
        .poll_key = struct {
            fn mockPollKey() callconv(.c) u8 {
                return 0;
            }
        }.mockPollKey,
        .sleep_ms = struct {
            fn mockSleep(_: u64) callconv(.c) void {}
        }.mockSleep,
        .alloc_pages = struct {
            fn mockAllocPages(_: usize) callconv(.c) ?[*]u8 {
                return null;
            }
        }.mockAllocPages,
    };

    init(&mock_table);

    TestState.called = false;
    TestState.length = 0;

    log("Test message");

    try std.testing.expect(TestState.called);
    try std.testing.expect(TestState.length == 12); // "Test message" length
}

test "User Runtime - drawRect Wrapper Passes Parameters" {
    // Track that drawRect was called with correct parameters
    const TestState = struct {
        var called: bool = false;
        var last_x: u32 = 0;
        var last_y: u32 = 0;
        var last_w: u32 = 0;
        var last_h: u32 = 0;
        var last_color: u32 = 0;

        fn mockDrawRect(x: u32, y: u32, w: u32, h: u32, color: u32) callconv(.c) void {
            called = true;
            last_x = x;
            last_y = y;
            last_w = w;
            last_h = h;
            last_color = color;
        }
    };

    const mock_table = KernelTable{
        .magic = table_def.KERNEL_TABLE_MAGIC,
        .log = struct {
            fn mockLog(_: [*]const u8, _: usize) callconv(.c) void {}
        }.mockLog,
        .draw_rect = TestState.mockDrawRect,
        .poll_key = struct {
            fn mockPollKey() callconv(.c) u8 {
                return 0;
            }
        }.mockPollKey,
        .sleep_ms = struct {
            fn mockSleep(_: u64) callconv(.c) void {}
        }.mockSleep,
        .alloc_pages = struct {
            fn mockAllocPages(_: usize) callconv(.c) ?[*]u8 {
                return null;
            }
        }.mockAllocPages,
    };

    init(&mock_table);

    TestState.called = false;
    drawRect(10, 20, 30, 40, 0xFF00FF00);

    try std.testing.expect(TestState.called);
    try std.testing.expect(TestState.last_x == 10);
    try std.testing.expect(TestState.last_y == 20);
    try std.testing.expect(TestState.last_w == 30);
    try std.testing.expect(TestState.last_h == 40);
    try std.testing.expect(TestState.last_color == 0xFF00FF00);
}

test "User Runtime - sleep Wrapper Passes Milliseconds" {
    // Track that sleep was called with correct duration
    const TestState = struct {
        var called: bool = false;
        var last_ms: u64 = 0;

        fn mockSleep(ms: u64) callconv(.c) void {
            called = true;
            last_ms = ms;
        }
    };

    const mock_table = KernelTable{
        .magic = table_def.KERNEL_TABLE_MAGIC,
        .log = struct {
            fn mockLog(_: [*]const u8, _: usize) callconv(.c) void {}
        }.mockLog,
        .draw_rect = struct {
            fn mockDrawRect(_: u32, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}
        }.mockDrawRect,
        .poll_key = struct {
            fn mockPollKey() callconv(.c) u8 {
                return 0;
            }
        }.mockPollKey,
        .sleep_ms = TestState.mockSleep,
        .alloc_pages = struct {
            fn mockAllocPages(_: usize) callconv(.c) ?[*]u8 {
                return null;
            }
        }.mockAllocPages,
    };

    init(&mock_table);

    TestState.called = false;
    TestState.last_ms = 0;
    sleep(100);

    try std.testing.expect(TestState.called);
    try std.testing.expect(TestState.last_ms == 100);
}

test "User Runtime - allocPages Wrapper Returns null" {
    const mock_table = KernelTable{
        .magic = table_def.KERNEL_TABLE_MAGIC,
        .log = struct {
            fn mockLog(_: [*]const u8, _: usize) callconv(.c) void {}
        }.mockLog,
        .draw_rect = struct {
            fn mockDrawRect(_: u32, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}
        }.mockDrawRect,
        .poll_key = struct {
            fn mockPollKey() callconv(.c) u8 {
                return 0;
            }
        }.mockPollKey,
        .sleep_ms = struct {
            fn mockSleep(_: u64) callconv(.c) void {}
        }.mockSleep,
        .alloc_pages = struct {
            fn mockAllocPages(_: usize) callconv(.c) ?[*]u8 {
                return null;
            }
        }.mockAllocPages,
    };

    init(&mock_table);
    const result = allocPages(1);
    try std.testing.expect(result == null);
}

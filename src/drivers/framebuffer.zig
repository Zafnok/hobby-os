const std = @import("std");
const limine = @import("../limine_import.zig").C;

extern var framebuffer_request: limine.struct_limine_framebuffer_request;

/// Retrieves the first available Limine framebuffer from the bootloader response.
/// Returns null if no framebuffer is found.
pub fn getFramebuffer() ?*limine.struct_limine_framebuffer {
    const response_ptr = @as(*volatile ?*limine.struct_limine_framebuffer_response, &framebuffer_request.response).*;
    if (response_ptr) |response| {
        if (response.framebuffer_count >= 1) {
            return response.framebuffers[0];
        }
    }
    return null;
}

/// Draws a single pixel at the specified (x, y) coordinates with the given color.
/// Clips against the framebuffer dimensions.
pub fn putPixel(fb: *limine.struct_limine_framebuffer, x: u64, y: u64, color: u32) void {
    if (x >= fb.width or y >= fb.height) return;

    const fb_ptr: [*]u32 = @ptrCast(@alignCast(fb.address));
    // pitch is in bytes, so for u32 (4 bytes) we divide by 4.
    // In a real generic driver we might handle bpp, but Limine 32bpp is standard.
    const index = (y * (fb.pitch / 4)) + x;
    fb_ptr[index] = color;
}

/// Draws a filled rectangle at (x, y) with the specified width, height, and color.
pub fn drawRect(fb: *limine.struct_limine_framebuffer, x: u64, y: u64, width: u64, height: u64, color: u32) void {
    const serial = @import("../kernel/serial.zig");
    // Sanity check
    if (fb.address == null) {
        serial.err("FATAL: Framebuffer address is NULL in drawRect");
        return;
    }

    var cy: u64 = 0;
    while (cy < height) : (cy += 1) {
        var cx: u64 = 0;
        while (cx < width) : (cx += 1) {
            putPixel(fb, x + cx, y + cy, color);
        }
    }
}

/// Fills the entire framebuffer with a single color.
pub fn fill(fb: *limine.struct_limine_framebuffer, color: u32) void {
    const serial = @import("../kernel/serial.zig");
    // Sanity check
    if (fb.address == null) {
        serial.err("FATAL: Framebuffer address is NULL in fill");
        return;
    }

    const fb_ptr: [*]u32 = @ptrCast(@alignCast(fb.address));
    // Note: This naive filling assumes pitch == width * 4.
    // A safer way is row by row if pitch includes padding.

    var y: u64 = 0;
    while (y < fb.height) : (y += 1) {
        var x: u64 = 0;
        while (x < fb.width) : (x += 1) {
            const index = (y * (fb.pitch / 4)) + x;
            fb_ptr[index] = color;
        }
    }
}

/// Draws a filled circle centered at (cx, cy) with the specified radius and color.
pub fn fillCircle(fb: *limine.struct_limine_framebuffer, cx: u64, cy: u64, radius: u64, color: u32) void {
    const r2 = radius * radius;
    // Bounding box optimization
    const start_x = if (cx > radius) cx - radius else 0;
    const end_x = if (cx + radius < fb.width) cx + radius else fb.width - 1;
    const start_y = if (cy > radius) cy - radius else 0;
    const end_y = if (cy + radius < fb.height) cy + radius else fb.height - 1;

    var y: u64 = start_y;
    while (y <= end_y) : (y += 1) {
        var x: u64 = start_x;
        while (x <= end_x) : (x += 1) {
            // distance check: (x-cx)^2 + (y-cy)^2 <= r^2
            // Use i64 to avoid underflow/overflow logic with u64
            const dx: i64 = @as(i64, @intCast(x)) - @as(i64, @intCast(cx));
            const dy: i64 = @as(i64, @intCast(y)) - @as(i64, @intCast(cy));
            if (dx * dx + dy * dy <= r2) {
                putPixel(fb, x, y, color);
            }
        }
    }
}

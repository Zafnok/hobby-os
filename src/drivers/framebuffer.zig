const std = @import("std");
const limine = @cImport({
    @cInclude("limine.h");
});

extern var framebuffer_request: limine.struct_limine_framebuffer_request;

pub fn getFramebuffer() ?*limine.struct_limine_framebuffer {
    const response_ptr = @as(*volatile ?*limine.struct_limine_framebuffer_response, &framebuffer_request.response).*;
    if (response_ptr) |response| {
        if (response.framebuffer_count >= 1) {
            return response.framebuffers[0];
        }
    }
    return null;
}

pub fn drawRedSquare(fb: *limine.struct_limine_framebuffer) void {
    const serial = @import("../kernel/serial.zig");
    serial.debug("Drawing Red Square");

    // Debug values
    const addr_val = @intFromPtr(fb.address);
    serial.debug("FB Address:");
    serial.printHex(.debug, addr_val);

    serial.debug("FB Width:");
    serial.printHex(.debug, fb.width);

    serial.debug("FB Height:");
    serial.printHex(.debug, fb.height);

    serial.debug("FB Pitch:");
    serial.printHex(.debug, fb.pitch);

    // Check if address is null or suspiciously low
    if (addr_val == 0) {
        serial.err("FATAL: Framebuffer address is NULL");
        return;
    }

    // Attempt single write first to test mapping
    serial.debug("Attempting single write to [0]...");
    const fb_ptr: [*]u32 = @ptrCast(@alignCast(fb.address));
    fb_ptr[0] = 0xFFFFFFFF;
    serial.debug("Single write success.");

    const fb_width = fb.width;
    const fb_height = fb.height;
    const fb_pitch = fb.pitch;

    // White background
    serial.debug("Filling Background...");
    for (0..fb_height) |y| {
        for (0..fb_width) |x| {
            const index = (y * (fb_pitch / 4)) + x;
            fb_ptr[index] = 0xFFFFFFFF;
        }
    }
    serial.debug("Background Filled.");

    // Red Square
    for (100..200) |y| {
        for (100..200) |x| {
            const index = (y * (fb_pitch / 4)) + x;
            fb_ptr[index] = 0xFFFF0000;
        }
    }
    serial.debug("Red Square Drawn.");
}

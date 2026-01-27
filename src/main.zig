const std = @import("std");
const limine = @import("limine.zig");

// We now import these from entry.S
// Define requests here to ensure they are exported and kept
// Requests defined in requests.c
extern var base_revision: limine.BaseRevision;
extern var framebuffer_request: limine.FramebufferRequest;
// Extern HHDM (we need a struct for it in main, but treating as ptr for check is enough)
extern var hhdm_request: anyopaque;

// Helper to write to IO port
fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

// Simple serial print (COM1)
fn log(msg: []const u8) void {
    for (msg) |c| {
        outb(0x3F8, c);
    }
    outb(0x3F8, '\n');
}

export fn kmain() callconv(.c) void {
    log("Kernel Started");

    // Check Address
    if (@intFromPtr(&base_revision) < 0xffffffff80000000) {
        log("WARNING: Base Revision address seems low/wrong.");
    }

    // Check Base Revision
    const rev = @as(*volatile u64, &base_revision.revision).*;

    if (rev == 0xFFFF) {
        log("FATAL: Base Revision is still 0xFFFF. Limine did NOT process requests.");
    } else {
        log("Base Revision updated by Limine (Success).");
    }

    // Check HHDM
    const hhdm_ptr = @intFromPtr(&hhdm_request);
    if (hhdm_ptr >= 0xffffffff80000000) {
        log("DEBUG: HHDM Ptr is in High Half (Valid Range)");
    } else {
        log("DEBUG: HHDM Ptr is Low/Invalid!");
    }

    const hhdm_resp = @as(*volatile u64, @ptrFromInt(hhdm_ptr + 40)).*;
    if (hhdm_resp != 0) {
        log("HHDM Request Satisfied!");
        const hhdm_offset = @as(*volatile u64, @ptrFromInt(hhdm_resp)).*;
        _ = hhdm_offset;
    } else {
        log("HHDM Request Response is NULL.");
    }

    // Volatile read of the response pointer
    const response_ptr = @as(*volatile ?*limine.FramebufferResponse, &framebuffer_request.response).*;

    // FALLBACK VARIABLES
    var fb_ptr: [*]u32 = undefined;
    var fb_width: u64 = 0;
    var fb_height: u64 = 0;
    var fb_pitch: u64 = 0;

    if (response_ptr) |response| {
        if (response.framebuffer_count >= 1) {
            const fb = response.framebuffers[0];
            fb_ptr = @ptrFromInt(@intFromPtr(fb.address));
            fb_width = fb.width;
            fb_height = fb.height;
            fb_pitch = fb.pitch;
            log("Framebuffer obtained from Limine.");
        }
    } else {
        log("Error: Limine failed to provide a framebuffer.");
    }

    if (fb_width > 0) {
        // White background
        for (0..fb_height) |y| {
            for (0..fb_width) |x| {
                const index = (y * (fb_pitch / 4)) + x;
                fb_ptr[index] = 0xFFFFFFFF;
            }
        }

        // Red Square
        for (100..200) |y| {
            for (100..200) |x| {
                const index = (y * (fb_pitch / 4)) + x;
                fb_ptr[index] = 0xFFFF0000;
            }
        }
        log("Drawing done. Hanging.");
    } else {
        log("Hanging.");
    }

    while (true) {
        asm volatile ("hlt");
    }
}

fn shutdown() noreturn {
    log("Shutting down (hanging loop)");
    // Hang instead of crash to allow inspection
    while (true) {}
}

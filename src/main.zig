const std = @import("std");
const limine = @cImport({
    @cInclude("limine.h");
});

// We now import these from entry.S
// Define requests here to ensure they are exported and kept
// Requests defined in requests.c (now limine.c)

// Base revision is now [3]u64 in requests.c
extern var base_revision: [3]u64;
extern var framebuffer_request: limine.struct_limine_framebuffer_request;
// Extern HHDM
extern var hhdm_request: limine.struct_limine_hhdm_request;

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

fn checkBaseRevision() void {
    // Check Address
    if (@intFromPtr(&base_revision) < 0xffffffff80000000) {
        log("WARNING: Base Revision address seems low/wrong.");
    }

    // Check Base Revision
    // In strict C macro: LIMINE_BASE_REVISION_SUPPORTED(VAR) is VAR[2] == 0
    // VAR[1] is the revision.
    const supported = @as(*volatile u64, &base_revision[2]).*;
    const rev = @as(*volatile u64, &base_revision[1]).*;
    _ = rev;

    if (supported != 0) {
        log("FATAL: Base Revision 3 NOT Supported by Limine.");
    } else {
        log("Base Revision Supported.");
    }
}

fn processHhdmResponse() void {
    // Check HHDM
    const hhdm_ptr = @intFromPtr(&hhdm_request);
    if (hhdm_ptr >= 0xffffffff80000000) {
        log("DEBUG: HHDM Ptr is in High Half (Valid Range)");
    } else {
        log("DEBUG: HHDM Ptr is Low/Invalid!");
    }

    const hhdm_resp = @as(*volatile ?*limine.struct_limine_hhdm_response, &hhdm_request.response).*;
    if (hhdm_resp) |resp| {
        log("HHDM Request Satisfied!");
        const offset = resp.offset;
        _ = offset;
    } else {
        log("HHDM Request Response is NULL.");
    }
}

fn getFramebuffer() ?*limine.struct_limine_framebuffer {
    const response_ptr = @as(*volatile ?*limine.struct_limine_framebuffer_response, &framebuffer_request.response).*;
    if (response_ptr) |response| {
        if (response.framebuffer_count >= 1) {
            return response.framebuffers[0];
        }
    }
    return null;
}

fn drawRedSquare(fb: *limine.struct_limine_framebuffer) void {
    const fb_ptr: [*]u32 = @ptrCast(@alignCast(fb.address));
    const fb_width = fb.width;
    const fb_height = fb.height;
    const fb_pitch = fb.pitch;

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
}

export fn kmain() callconv(.c) void {
    log("Kernel Started");

    checkBaseRevision();
    processHhdmResponse();

    if (getFramebuffer()) |fb| {
        log("Framebuffer obtained from Limine.");
        drawRedSquare(fb);
        log("Drawing done. Hanging.");
    } else {
        log("Error: Limine failed to provide a framebuffer.");
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

const std = @import("std");
const limine = @cImport({
    @cInclude("limine.h");
});

// We now import these from entry.S
// Define requests here to ensure they are exported and kept
// Requests defined in requests.c

// Base revision is now [3]u64 in requests.c
extern var base_revision: [3]u64;
extern var framebuffer_request: limine.struct_limine_framebuffer_request;
// Extern HHDM (we need a struct for it in main, but treating as ptr for check is enough)
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

export fn kmain() callconv(.c) void {
    log("Kernel Started");

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

    // Volatile read of the response pointer
    const response_ptr = @as(*volatile ?*limine.struct_limine_framebuffer_response, &framebuffer_request.response).*;

    var fb_ptr: [*]u32 = undefined;
    var fb_width: u64 = 0;
    var fb_height: u64 = 0;
    var fb_pitch: u64 = 0;

    if (response_ptr) |response| {
        if (response.framebuffer_count >= 1) {
            // response.framebuffers is a pointer to an array of pointers to framebuffer structs
            const fbs = response.framebuffers;
            // We need to access fbs[0]
            const fb = fbs[0];

            // fb is [*c]struct... so we must dereference it to access fields.
            // Assuming non-null because count >= 1.
            fb_ptr = @ptrCast(@alignCast(fb.*.address));
            fb_width = fb.*.width;
            fb_height = fb.*.height;
            fb_pitch = fb.*.pitch;
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

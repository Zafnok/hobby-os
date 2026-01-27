const std = @import("std");
const limine = @cImport({
    @cInclude("limine.h");
});
const serial = @import("kernel/serial.zig");
const framebuffer = @import("drivers/framebuffer.zig");

// We now import these from entry.S
// Define requests here to ensure they are exported and kept
// Requests defined in requests.c (now limine.c)

// Base revision is now [3]u64 in requests.c
extern var base_revision: [3]u64;

// Extern HHDM
extern var hhdm_request: limine.struct_limine_hhdm_request;

fn checkBaseRevision() void {
    // Check Address
    if (@intFromPtr(&base_revision) < 0xffffffff80000000) {
        serial.warn("Base Revision address seems low/wrong.");
    }

    // Check Base Revision
    // In strict C macro: LIMINE_BASE_REVISION_SUPPORTED(VAR) is VAR[2] == 0
    // VAR[1] is the revision.
    const supported = @as(*volatile u64, &base_revision[2]).*;
    const rev = @as(*volatile u64, &base_revision[1]).*;
    _ = rev;

    if (supported != 0) {
        serial.err("FATAL: Base Revision 3 NOT Supported by Limine.");
    } else {
        serial.info("Base Revision Supported.");
    }
}

fn processHhdmResponse() void {
    // Check HHDM
    const hhdm_ptr = @intFromPtr(&hhdm_request);
    if (hhdm_ptr >= 0xffffffff80000000) {
        serial.debug("HHDM Ptr is in High Half (Valid Range)");
    } else {
        serial.warn("HHDM Ptr is Low/Invalid!");
    }

    const hhdm_resp = @as(*volatile ?*limine.struct_limine_hhdm_response, &hhdm_request.response).*;
    if (hhdm_resp) |resp| {
        serial.info("HHDM Request Satisfied!");
        const offset = resp.offset;
        serial.debug("HHDM Offset:");
        serial.printHex(.debug, offset);
    } else {
        serial.warn("HHDM Request Response is NULL.");
    }
}

export fn kmain() callconv(.c) void {
    serial.info("Kernel Started");

    checkBaseRevision();
    processHhdmResponse();

    if (framebuffer.getFramebuffer()) |fb| {
        serial.info("Framebuffer obtained from Limine.");
        framebuffer.drawRedSquare(fb);
        serial.info("Drawing done. Hanging.");
    } else {
        serial.err("Error: Limine failed to provide a framebuffer.");
        serial.err("Hanging.");
    }

    while (true) {
        asm volatile ("hlt");
    }
}

fn shutdown() noreturn {
    serial.info("Shutting down (hanging loop)");
    // Hang instead of crash to allow inspection
    while (true) {}
}

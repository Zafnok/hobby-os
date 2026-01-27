const std = @import("std");
const limine = @import("limine_import.zig").C;
const serial = @import("kernel/serial.zig");
const memory = @import("memory/layout.zig");
const framebuffer = @import("drivers/framebuffer.zig");
const pmm = @import("memory/pmm.zig");
const fun = @import("fun/demos.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");

// We now import these from entry.S
// Define requests here to ensure they are exported and kept
// Requests defined in requests.c (now limine.c)

// Base revision is now [3]u64 in requests.c
extern var base_revision: [3]u64;

// Extern HHDM
extern var hhdm_request: limine.struct_limine_hhdm_request;

/// Checks if the Limine bootloader supports the requested base revision.
/// Logs an error if not supported.
fn checkBaseRevision() void {
    // Check Address
    if (@intFromPtr(&base_revision) < memory.HIGHER_HALF_BASE) {
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

/// Processes the Higher Half Direct Map (HHDM) response from Limine.
/// Validates the pointer location and logs the offset if successful.
fn processHhdmResponse() void {
    // Check HHDM
    const hhdm_ptr = @intFromPtr(&hhdm_request);
    if (hhdm_ptr >= memory.HIGHER_HALF_BASE) {
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

/// The kernel entry point called by the startup code.
/// Initializes GDT, IDT, PMM, and the Framebuffer.
export fn kmain() callconv(.c) void {
    serial.info("Kernel Started");

    gdt.init();
    serial.info("GDT Initialized");
    idt.init();
    serial.info("IDT Initialized");

    pmm.init();

    // Verification: PMM
    if (pmm.allocatePage()) |page1| {
        serial.info("PMM Test: Allocated page at: 0x");
        serial.printHex(.info, page1);

        if (pmm.allocatePage()) |page2| {
            serial.info("PMM Test: Allocated page at: 0x");
            serial.printHex(.info, page2);
            pmm.freePage(page2);
            serial.info("PMM Test: Freed page 2");
        }
        pmm.freePage(page1);
        serial.info("PMM Test: Freed page 1");
    } else {
        serial.err("PMM Test: Allocation FAILED!");
    }

    // Test IDT: Trigger Breakpoint Exception
    // asm volatile ("int $3");

    checkBaseRevision();
    processHhdmResponse();

    if (framebuffer.getFramebuffer()) |fb| {
        serial.info("Framebuffer obtained from Limine.");
        fun.drawSmileyFace(fb);
        serial.info("Drawing done. Hanging.");
    } else {
        serial.err("Error: Limine failed to provide a framebuffer.");
        serial.err("Hanging.");
    }

    while (true) {
        asm volatile ("hlt");
    }
}

/// Shuts down the kernel by entering an infinite loop.
fn shutdown() noreturn {
    serial.info("Shutting down (hanging loop)");
    // Hang instead of crash to allow inspection
    while (true) {}
}

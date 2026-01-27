const std = @import("std");
const limine = @import("limine_import.zig").C;
pub const serial = @import("kernel/serial.zig");
const memory = @import("memory/layout.zig");
const framebuffer = @import("drivers/framebuffer.zig");
pub const pmm = @import("memory/pmm.zig");
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
/// Initializes the kernel core subsystems (Serial, GDT, IDT, PMM).
/// This is used by both the main kernel entry and the test runner.
pub fn initKernel() void {
    serial.info("Kernel Initialization Started");

    gdt.init();
    serial.info("GDT Initialized");
    idt.init();
    serial.info("IDT Initialized");

    pmm.init();
    // pmm.init() logs its own completion
}

/// The kernel entry point called by the startup code.
/// The kernel entry point called by the startup code.
/// The kernel entry point called by the startup code.
/// The kernel entry point called by the startup code.
fn kmain_impl() callconv(.c) void {
    serial.info("Kernel Started (Production Mode)");
    initKernel();

    checkBaseRevision();
    processHhdmResponse();

    // Check for Framebuffer and run demo if available
    if (framebuffer.getFramebuffer()) |fb| {
        serial.info("Framebuffer available. Running smiley demo...");
        fun.drawSmileyFace(fb);
        serial.info("Demo complete.");
    } else {
        serial.warn("No Framebuffer found. Skipping demo.");
    }

    while (true) {
        asm volatile ("hlt");
    }
}

// Conditionally export kmain based on build mode
comptime {
    if (!@import("builtin").is_test) {
        @export(@as(*const fn () callconv(.c) void, &kmain_impl), .{ .name = "kmain", .linkage = .strong });
    }
}

test "PMM Allocation and Free" {
    // Note: initKernel() must be called by the runner before this test.
    const page1 = pmm.allocatePage();
    try std.testing.expect(page1 != null);
    serial.info("Test: Allocated Page 1");

    const page2 = pmm.allocatePage();
    try std.testing.expect(page2 != null);
    serial.info("Test: Allocated Page 2");

    // Addresses should be distinct
    try std.testing.expect(page1.? != page2.?);

    pmm.freePage(page2.?);
    serial.info("Test: Freed Page 2");

    pmm.freePage(page1.?);
    serial.info("Test: Freed Page 1");
}

test "Framebuffer Access" {
    const fb = framebuffer.getFramebuffer();
    if (fb) |f| {
        try std.testing.expect(f.width > 0);
        try std.testing.expect(f.height > 0);

        // Try drawing a test pixel (top left)
        // We don't want to mess up the screen too much during tests, but a pixel is fine.
        framebuffer.putPixel(f, 0, 0, 0xFFFFFFFF);
    } else {
        // If we are testing on a system without FB, we might skip.
        // But our QEMU setup should have it.
        serial.warn("Framebuffer test skipped (no FB)");
    }
}

/// Shuts down the kernel by entering an infinite loop.
fn shutdown() noreturn {
    serial.info("Shutting down (hanging loop)");
    // Hang instead of crash to allow inspection
    while (true) {}
}

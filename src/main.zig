const std = @import("std");
const limine = @import("limine_import.zig").C;
pub const serial = @import("kernel/serial.zig");
const memory = @import("memory/layout.zig");
const framebuffer = @import("drivers/graphics/framebuffer.zig");
pub const pmm = @import("memory/pmm.zig");
pub const heap = @import("memory/heap.zig");
const fun = @import("fun/demos.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");
const pic = @import("arch/x86_64/pic.zig");
const pks = @import("arch/x86_64/pks.zig");
const vmm = @import("memory/vmm.zig");

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

/// Common kernel initialization logic.
/// Initializes the kernel core subsystems (Serial, GDT, IDT, PMM).
/// This is used by both the main kernel entry (kmain) and the test runner.
pub fn initKernel() void {
    serial.info("Kernel Initialization Started");

    gdt.init();
    serial.info("GDT Initialized");
    idt.init();
    serial.info("IDT Initialized");

    pks.init();

    pic.init();
    serial.info("PIC Initialized (Mapped to 32/40)");

    pmm.init();
    vmm.init();
    // pmm.init() logs its own completion

    heap.init();
}

/// The main kernel entry point implementation.
/// This function is exported as 'kmain' and is called by the assembly startup code (entry.S).
fn kmain_impl() callconv(.c) void {
    serial.info("Kernel Started (Production Mode)");
    initKernel();

    checkBaseRevision();
    processHhdmResponse();

    // --- Heap Verification ---
    {
        serial.info("Verification: Testing Kernel Heap...");
        var list = std.ArrayList(u32).initCapacity(heap.getAllocator(), 4) catch {
            serial.err("Heap: Failed to initCapacity");
            return;
        };
        defer list.deinit(heap.getAllocator());

        list.append(heap.getAllocator(), 123) catch serial.err("Heap: Failed append 1");
        list.append(heap.getAllocator(), 456) catch serial.err("Heap: Failed append 2");
        list.append(heap.getAllocator(), 789) catch serial.err("Heap: Failed append 3");

        if (list.items.len == 3 and list.items[2] == 789) {
            serial.info("Verification: Heap Works! ArrayList created and populated.");
        } else {
            serial.err("Verification: Heap Failed sanity check.");
        }
    }
    // -------------------------

    serial.info("Enabling Interrupts...");
    asm volatile ("sti");

    // Check for Framebuffer and run demo if available
    if (framebuffer.getFramebuffer()) |fb| {
        serial.info("Framebuffer available. Running smiley demo...");
        fun.drawSmileyFace(fb);
        serial.info("Smiley Demo complete. Waiting 1s...");

        // Delay ~1s
        const io = @import("arch/x86_64/io.zig");
        var i: usize = 0;
        // Increase loop significantly for QEMU/Virt
        while (i < 50_000_000) : (i += 1) {
            io.wait();
        }

        serial.info("Transitioning to Keyboard Demo...");

        // Initialize keyboard if not already (it is idempotent safely?)
        // Yes, init() unmasks IRQ.
        const keyboard = @import("drivers/keyboard.zig");
        keyboard.init();

        fun.runKeyboardDemo(fb);
    } else {
        serial.warn("No Framebuffer found. Skipping demos.");
    }

    // Fallback infinite loop if no framebuffer
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

test {
    // Force inclusions of tests in imported modules
    std.testing.refAllDecls(pmm);
    std.testing.refAllDecls(framebuffer);
}

/// Shuts down the kernel by entering an infinite loop.
fn shutdown() noreturn {
    serial.info("Shutting down (hanging loop)");
    // Hang instead of crash to allow inspection
    while (true) {}
}

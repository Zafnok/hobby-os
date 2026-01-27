const std = @import("std");
const builtin = @import("builtin");

// The test runner replaces the normal entry point in a test build.
// Since we are in a freestanding kernel, we must export the symbol expected by entry.S.
export fn kmain() callconv(.c) void {
    const root = @import("test_root");
    const serial = root.serial;

    // 1. Initialize Kernel Subsystems
    // We rely on the root file (main.zig) to provide an initialization function.
    if (@hasDecl(root, "initKernel")) {
        root.initKernel();
    } else {
        serial.err("Test Runner: root file references no 'initKernel' function!");
        shutdown();
    }

    serial.info("\n==========================");
    serial.info("   RUNNING KERNEL TESTS   ");
    serial.info("==========================\n");

    // 2. Iterate and Run Tests
    const tests = builtin.test_functions;
    var passed: usize = 0;
    var failed: usize = 0;

    for (tests) |t| {
        serial.info("[TEST] ");
        serial.info(t.name);
        serial.info(" ... ");

        if (t.func()) {
            passed += 1;
            serial.info("PASS\n");
        } else |err| {
            failed += 1;
            serial.info("FAIL (");
            serial.info(@errorName(err));
            serial.info(")\n");

            // In a more advanced runner, we could print stack traces here
        }
    }

    // 3. Summary
    serial.info("\n--------------------------");
    serial.info("Test Summary: ");

    // Manual integer printing since we don't have a formatted printer coupled to serial yet
    // (Serial only accepts strings in this codebase so far, based on previous edits)
    // Actually, serial.zig usually has printHex or similar.
    // We'll just print simple status.

    if (failed == 0) {
        serial.info("ALL TESTS PASSED\n");
    } else {
        serial.info("SOME TESTS FAILED\n");
    }

    shutdown();
}

fn shutdown() noreturn {
    // QEMU debug exit
    // Port 0x604, value can be anything (usually 0 or 1 signifies status)
    // We'll write 0 to exit 'successfully' (QEMU might map this to exit code 1 or 0 depending on version)
    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (@as(u8, 0)),
          [port] "{dx}" (@as(u16, 0x604)),
    );

    while (true) {
        asm volatile ("hlt");
    }
}

pub fn main() void {
    // This function is required by the Zig build system's default test handling,
    // but since we override the entry point with kmain and use freestanding,
    // this might not be called. However, providing it satisfies the interface.
    // In our case, entry.S calls kmain directly.
}

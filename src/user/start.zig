/// User Program Entry Point
///
/// This module provides the _start entry point that all userspace programs use.
/// The ELF loader jumps to _start and passes a pointer to the kernel table.
///
/// _start is responsible for:
/// 1. Receiving the kernel table pointer from the ELF loader
/// 2. Initializing the user runtime library with the table
/// 3. Calling the user's main() function
/// 4. Entering an infinite halt loop if main returns (safety net)
const lib = @import("lib.zig");
const table_def = @import("../kernel/table.zig");

/// Entry point for all userspace programs.
/// Called by the ELF loader with a pointer to the kernel table in RDI (C calling convention).
///
/// This function never returns. If main() returns, we halt the CPU gracefully
/// rather than jumping to garbage memory.
export fn _start(table: *const table_def.KernelTable) callconv(.c) noreturn {
    // Initialize the user runtime library with the kernel table
    lib.init(table);

    // Call the user's main function
    // NOTE: main() is expected to be defined by the userspace program (e.g., snake.zig)
    // and should be declared as: pub fn main() void
    main();

    // If we get here, main() returned - this should never happen in our OS
    // since we don't have process termination yet. Games like Snake should
    // run forever in a loop.
    //
    // Halt gracefully instead of jumping to random memory
    while (true) {
        asm volatile ("hlt");
    }
}

/// User's main function - must be defined by the userspace program.
/// This is a weak declaration that will be overridden by the actual program.
extern fn main() void;

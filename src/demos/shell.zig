const std = @import("std");
const limine = @import("../limine_import.zig").C;
const framebuffer = @import("../drivers/graphics/framebuffer.zig");
const font = @import("../drivers/graphics/font.zig");
const keyboard = @import("../drivers/keyboard.zig");
const serial = @import("../kernel/serial.zig");
const elf = @import("../loaders/elf.zig");
const table = @import("../kernel/table.zig");

/// Runs the interactive shell.
/// This function enters an infinite loop.
pub fn runShell(fb: *limine.struct_limine_framebuffer, modules: ?*limine.struct_limine_module_response) noreturn {
    // Clear screen first
    framebuffer.fill(fb, 0xFF000000); // Black background

    var cursor_x: u64 = 10;
    var cursor_y: u64 = 10;

    // Command Buffer
    var buffer: [256]u8 = undefined;
    var buffer_idx: usize = 0;

    const prompt = "> ";
    printStr(fb, &cursor_x, &cursor_y, prompt);

    while (true) {
        asm volatile ("hlt");

        // Process Input
        while (keyboard.pop()) |char| {
            handleCharacter(fb, char, &buffer, &buffer_idx, &cursor_x, &cursor_y, prompt, modules);
        }
    }
}

/// Handles a single character input from the keyboard
fn handleCharacter(
    fb: *limine.struct_limine_framebuffer,
    char: u8,
    buffer: *[256]u8,
    buffer_idx: *usize,
    cursor_x: *u64,
    cursor_y: *u64,
    prompt: []const u8,
    modules: ?*limine.struct_limine_module_response,
) void {
    if (char == '\n' or char == 10) {
        handleNewline(fb, buffer, buffer_idx, cursor_x, cursor_y, prompt, modules);
    } else if (char == 8) {
        handleBackspace(fb, buffer_idx, cursor_x, cursor_y);
    } else {
        handlePrintableChar(fb, buffer, buffer_idx, cursor_x, cursor_y, char);
    }

    // Wrap logic (basic)
    if (cursor_x.* >= fb.width - 10) {
        cursor_x.* = 10;
        cursor_y.* += 10;
    }
}

/// Handles newline/enter key: processes the command and resets the prompt
fn handleNewline(
    fb: *limine.struct_limine_framebuffer,
    buffer: *[256]u8,
    buffer_idx: *usize,
    cursor_x: *u64,
    cursor_y: *u64,
    prompt: []const u8,
    modules: ?*limine.struct_limine_module_response,
) void {
    if (buffer_idx.* > 0) {
        const cmd = buffer[0..buffer_idx.*];

        // Move to next line for output
        cursor_x.* = 10;
        cursor_y.* += 10;

        processCommand(fb, cmd, cursor_x, cursor_y, modules);

        // Reset buffer
        buffer_idx.* = 0;
    } else {
        cursor_x.* = 10;
        cursor_y.* += 10;
    }

    // New Prompt
    printStr(fb, cursor_x, cursor_y, prompt);
}

/// Processes a command and executes the appropriate action
fn processCommand(
    fb: *limine.struct_limine_framebuffer,
    cmd: []const u8,
    cursor_x: *u64,
    cursor_y: *u64,
    modules: ?*limine.struct_limine_module_response,
) void {
    if (std.mem.eql(u8, cmd, "load test.elf")) {
        loadTestElf(fb, cursor_x, cursor_y, modules);
    } else {
        printStr(fb, cursor_x, cursor_y, "Unknown command: ");
        printStr(fb, cursor_x, cursor_y, cmd);
        cursor_x.* = 10;
        cursor_y.* += 10;
    }
}

/// Loads and executes the test.elf module
fn loadTestElf(
    fb: *limine.struct_limine_framebuffer,
    cursor_x: *u64,
    cursor_y: *u64,
    modules: ?*limine.struct_limine_module_response,
) void {
    printStr(fb, cursor_x, cursor_y, "Loading test.elf...");
    cursor_x.* = 10;
    cursor_y.* += 10;

    const found = findAndLoadElf(fb, cursor_x, cursor_y, modules);

    if (!found) {
        printStr(fb, cursor_x, cursor_y, "Module 'test.elf' not found.");
    }
}

/// Searches for test.elf in modules and loads it if found
fn findAndLoadElf(
    fb: *limine.struct_limine_framebuffer,
    cursor_x: *u64,
    cursor_y: *u64,
    modules: ?*limine.struct_limine_module_response,
) bool {
    const mods = modules orelse return false;

    var i: usize = 0;
    const count = mods.module_count;
    const list = mods.modules;

    while (i < count) : (i += 1) {
        const mod = list[i];
        // Dereference C pointer
        const file = mod.*;
        const path = std.mem.span(file.path);

        if (std.mem.indexOf(u8, path, "test.elf") != null) {
            executeElf(fb, cursor_x, cursor_y, &file, path);
            return true;
        }
    }

    return false;
}

/// Executes an ELF file
fn executeElf(
    fb: *limine.struct_limine_framebuffer,
    cursor_x: *u64,
    cursor_y: *u64,
    file: *const limine.struct_limine_file,
    path: []const u8,
) void {
    printStr(fb, cursor_x, cursor_y, "Found module: ");
    printStr(fb, cursor_x, cursor_y, path);
    cursor_x.* = 10;
    cursor_y.* += 10;

    // Load it
    if (elf.loadElf(@ptrCast(file.address), file.size)) |entry| {
        printStr(fb, cursor_x, cursor_y, "Jumping to entry point...");

        // Pass the kernel table to userspace via C calling convention (RDI)
        const entry_fn = @as(*const fn (ktable: *const table.KernelTable) callconv(.c) void, @ptrFromInt(entry));
        entry_fn(&table.table);

        // If it returns (unlikely for our test), we are back?
        // It might mess up stack/regs but let's hope for best.
    } else |_| {
        printStr(fb, cursor_x, cursor_y, "Load Failed!");
        serial.err("ELF Load Failed");
    }
}

/// Handles backspace key: removes last character from buffer and screen
fn handleBackspace(
    fb: *limine.struct_limine_framebuffer,
    buffer_idx: *usize,
    cursor_x: *u64,
    cursor_y: *u64,
) void {
    if (buffer_idx.* > 0) {
        buffer_idx.* -= 1;

        // Visual backspace
        if (cursor_x.* > 10) {
            cursor_x.* -= 9;
            // Overwrite with black (background color)
            // Width 9 (8 char + 1 padding), Height 8
            framebuffer.drawRect(fb, cursor_x.*, cursor_y.*, 9, 8, 0xFF000000);
        }
    }
}

/// Handles a printable character: adds to buffer and displays on screen
fn handlePrintableChar(
    fb: *limine.struct_limine_framebuffer,
    buffer: *[256]u8,
    buffer_idx: *usize,
    cursor_x: *u64,
    cursor_y: *u64,
    char: u8,
) void {
    if (buffer_idx.* < buffer.len) {
        buffer[buffer_idx.*] = char;
        buffer_idx.* += 1;

        font.drawChar(fb, cursor_x.*, cursor_y.*, char, 0xFFFFFFFF); // White text
        cursor_x.* += 9;
    }
}

fn printStr(fb: *limine.struct_limine_framebuffer, x: *u64, y: *u64, str: []const u8) void {
    for (str) |c| {
        font.drawChar(fb, x.*, y.*, c, 0xFFFFFFFF);
        x.* += 9;
        if (x.* >= fb.width - 10) {
            x.* = 10;
            y.* += 10;
        }
    }
}

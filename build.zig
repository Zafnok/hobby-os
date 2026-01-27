const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const optimize = b.standardOptimizeOption(.{});

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .pic = false, // Kernel code should generally not be PIC unless necessary
    });

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = kernel_mod,
    });

    kernel.addAssemblyFile(b.path("src/entry.S"));

    // Add C source for requests
    kernel.addCSourceFile(.{
        .file = b.path("src/limine.c"),
        .flags = &.{ "-nostdlib", "-ffreestanding" },
    });
    // Add Include Path for Limine (used by Zig imports)
    kernel.addIncludePath(b.path("src"));

    // Force LLVM/LLD
    kernel.use_llvm = true;
    kernel.use_lld = true;

    kernel.setLinkerScript(b.path("linker.ld"));

    // FIX: Use the dedicated field for max-page-size instead of addLinkerArg
    kernel.link_z_max_page_size = 0x1000;

    b.installArtifact(kernel);
}

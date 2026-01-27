const std = @import("std");

const LogLevel = enum {
    debug,
    info,
    warn,
    err,
};

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = std.Target.x86.featureSet(&.{
            .pku,
        }),
    });
    const optimize = b.standardOptimizeOption(.{});

    // Options
    const log_level = b.option(LogLevel, "log_level", "Minimum log level") orelse .info;

    // We create separate option sets for default (PKS on) and no-pks
    const options = b.addOptions();
    options.addOption(LogLevel, "log_level", log_level);
    options.addOption(bool, "expect_pks", true);

    const options_no_pks = b.addOptions();
    options_no_pks.addOption(LogLevel, "log_level", log_level);
    options_no_pks.addOption(bool, "expect_pks", false);

    // ======================================
    // Main Kernel Build
    // ======================================
    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .pic = false,
    });
    kernel_mod.addOptions("build_options", options);

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = kernel_mod,
    });

    configureKernel(b, kernel);
    b.installArtifact(kernel);

    // Run Step
    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-M",
        "q35",
        "-serial",
        "stdio",
        "-device",
        "isa-debug-exit,iobase=0x604,iosize=4",
        "-vga",
        "std",
        "-m",
        "512M",
        "-m",
        "512M",
        "-cpu",
        "max,+pks",
        "-kernel",
    });
    run_cmd.addArtifactArg(kernel);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the kernel in QEMU");
    run_step.dependOn(&run_cmd.step);

    // ======================================
    // Test Kernel Build (PKS Enabled - Default)
    // ======================================
    createTestStep(b, target, optimize, options, true, "test", "Run kernel tests (PKS Enabled)");

    // ======================================
    // Test Kernel Build (PKS Disabled)
    // ======================================
    createTestStep(b, target, optimize, options_no_pks, false, "test-no-pks", "Run kernel tests (PKS Disabled)");
}

fn createTestStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: *std.Build.Step.Options,
    enable_pks: bool,
    step_name: []const u8,
    step_desc: []const u8,
) void {
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .pic = false,
    });
    test_mod.addOptions("build_options", options);
    test_mod.addImport("test_root", test_mod);

    const kernel_test = b.addTest(.{
        .name = if (enable_pks) "kernel_test" else "kernel_test_no_pks",
        .root_module = test_mod,
        .test_runner = .{ .path = b.path("test/test_runner.zig"), .mode = .simple },
    });

    configureKernel(b, kernel_test);

    // ISO Creation -> QEMU
    const cp_cmd = b.addSystemCommand(&.{"cp"});
    cp_cmd.addArtifactArg(kernel_test);
    // Limine config expects /kernel, so we must overwrite it
    cp_cmd.addArg("dist/kernel");

    // Fix: xorriso needs the dist folder to exist and contain what we want
    // We reuse 'dist/' but we need to make sure we don't overwrite if running in parallel.
    // Ideally we'd use separate folders, but for now let's use separate ISO names.
    const iso_name = if (enable_pks) "test.iso" else "test_no_pks.iso";

    const iso_cmd = b.addSystemCommand(&.{ "xorriso", "-as", "mkisofs", "-b", "limine-bios-cd.bin", "-no-emul-boot", "-boot-load-size", "4", "-boot-info-table", "--efi-boot", "limine-uefi-cd.bin", "-efi-boot-part", "--efi-boot-image", "--protective-msdos-label", "-o", iso_name, "dist/" });
    iso_cmd.step.dependOn(&cp_cmd.step);

    const limine_deploy = b.addSystemCommand(&.{ "./limine", "bios-install", iso_name });
    limine_deploy.step.dependOn(&iso_cmd.step);

    // QEMU Flags
    const run_test_cmd = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-M",
        "q35",
        "-serial",
        "stdio",
        "-device",
        "isa-debug-exit,iobase=0x604,iosize=4",
        "-vga",
        "std",
        "-m",
        "512M",
        "-cdrom",
        iso_name,
        "-boot",
        "d",
    });

    if (enable_pks) {
        run_test_cmd.addArgs(&.{ "-cpu", "max,+pks" });
    } else {
        // Explicitly disable PKS or just don't add it (qemu64 default is off)
        // Use a CPU that naturally lacks PKS but has other modern features (e.g. Skylake-Server)
        run_test_cmd.addArgs(&.{ "-cpu", "Skylake-Server" });
    }

    run_test_cmd.step.dependOn(&limine_deploy.step);

    const test_step = b.step(step_name, step_desc);
    test_step.dependOn(&run_test_cmd.step);
}

/// Helper to apply common kernel configuration (assembly, linker script, C sources).
fn configureKernel(b: *std.Build, compile: *std.Build.Step.Compile) void {
    compile.addAssemblyFile(b.path("src/entry.S"));
    compile.addAssemblyFile(b.path("src/arch/x86_64/asm/interrupts.S"));

    // Add C source for requests
    compile.addCSourceFile(.{
        .file = b.path("src/limine.c"),
        .flags = &.{ "-nostdlib", "-ffreestanding" },
    });
    // Add Include Path for Limine (used by Zig imports)
    compile.addIncludePath(b.path("src"));

    // Force LLVM/LLD
    compile.use_llvm = true;
    compile.use_lld = true;

    compile.setLinkerScript(b.path("linker.ld"));

    // FIX: Use the dedicated field for max-page-size
    compile.link_z_max_page_size = 0x1000;
}

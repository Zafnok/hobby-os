const std = @import("std");
const serial = @import("../../kernel/serial.zig");

// Constants
const CR4_PKS_BIT: u64 = 1 << 24;
const MSR_IA32_PKRS: u32 = 0x691;
const CPUID_PKS_BIT: u32 = 1 << 31;

/// Protection Key Rights for Supervisor (PKRS) MSR wrapper
pub const Pkrs = struct {
    pub fn read() u32 {
        var low: u32 = 0;
        var high: u32 = 0;
        asm volatile ("rdmsr"
            : [low] "={eax}" (low),
              [high] "={edx}" (high),
            : [msr] "{ecx}" (MSR_IA32_PKRS),
        );
        return low;
    }

    pub fn write(val: u32) void {
        const high: u32 = 0; // PKRS is 32-bit, high bits reserved 0
        asm volatile ("wrmsr"
            :
            : [low] "{eax}" (val),
              [high] "{edx}" (high),
              [msr] "{ecx}" (MSR_IA32_PKRS),
        );
    }
};

/// Check if PKS is supported by hardware (CPUID.7.0.ECX[31])
pub fn checkSupport() bool {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    asm volatile (
        \\ cpuid
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [eax_in] "{eax}" (7),
          [ecx_in] "{ecx}" (0),
    );

    return (ecx & CPUID_PKS_BIT) != 0;
}

/// Initialize Protection Keys for Supervisor
pub fn init() void {
    serial.info("PKS: Checking support...");

    if (!checkSupport()) {
        serial.warn("PKS: Not supported by hardware. PKS will be disabled.");
        return;
    }

    // Enable PKS in CR4
    var cr4: u64 = undefined;
    asm volatile ("mov %%cr4, %[ret]"
        : [ret] "=r" (cr4),
    );

    cr4 |= CR4_PKS_BIT;

    asm volatile ("mov %[val], %%cr4"
        :
        : [val] "r" (cr4),
    );

    serial.info("PKS: Enabled in CR4.");

    // Initialize PKRS to 0 (allow all access) for now
    Pkrs.write(0);
    serial.info("PKS: PKRS initialized to 0.");
}

test "PKS Support Check" {
    const supported = checkSupport();
    if (supported) {
        std.debug.print("PKS IS Supported\n", .{});
    } else {
        std.debug.print("PKS IS NOT Supported\n", .{});
    }
}

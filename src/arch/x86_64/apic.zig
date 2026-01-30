const std = @import("std");
const io = @import("io.zig");
const serial = @import("../../kernel/serial.zig");
const limine = @import("../../limine_import.zig").C;

// TODO: Parse ACPI (MADT table) to get the actual Local APIC and IOAPIC physical addresses.
// For now, we use the standard defaults which QEMU (and most hardware) respects.
const LAPIC_PHYS_BASE = 0xFEE00000;
const IOAPIC_PHYS_BASE = 0xFEC00000;

// Access to HHDM Request (Defined in limine.c)
extern var hhdm_request: limine.struct_limine_hhdm_request;

fn getHhdmOffset() u64 {
    const resp = hhdm_request.response;
    if (resp == null) {
        // Fallback or Panic? For now, assume it exists or return 0 (which will likely crash but explicitly)
        // We can't easily log here if serial depends on something, but serial is usually safe.
        return 0;
    }
    return resp.*.offset;
}

fn getVirtualAddress(phys: u64) u64 {
    return phys + getHhdmOffset();
}

// Local APIC Registers (Offsets)
const LAPIC_ID = 0x0020;
const LAPIC_EOI = 0x00B0;
const LAPIC_SVR = 0x00F0; // Spurious Interrupt Vector Register
const LAPIC_ICR_LOW = 0x0300; // Interrupt Command Register Low
const LAPIC_ICR_HIGH = 0x0310; // Interrupt Command Register High
const LAPIC_LVT_TIMER = 0x0320;

// IOAPIC Registers (Offsets)
const IOAPIC_ID = 0x00;
const IOAPIC_VER = 0x01;
const IOAPIC_ARB = 0x02;
const IOAPIC_RED_TBL = 0x10; // Redirection Table entries start here (low/high pairs)

/// Read from Local APIC Register
fn lapicRead(offset: u64) u32 {
    const addr = getVirtualAddress(LAPIC_PHYS_BASE) + offset;
    const ptr = @as(*volatile u32, @ptrFromInt(addr));
    return ptr.*;
}

/// Write to Local APIC Register
fn lapicWrite(offset: u64, value: u32) void {
    const addr = getVirtualAddress(LAPIC_PHYS_BASE) + offset;
    const ptr = @as(*volatile u32, @ptrFromInt(addr));
    ptr.* = value;
}

/// Read from IOAPIC Register (Indirect Access)
/// Index Register: Base + 0x00
/// Data Register:  Base + 0x10
fn ioapicRead(reg: u32) u32 {
    const base = getVirtualAddress(IOAPIC_PHYS_BASE);
    const idx_ptr = @as(*volatile u32, @ptrFromInt(base + 0x00));
    const dat_ptr = @as(*volatile u32, @ptrFromInt(base + 0x10));

    idx_ptr.* = reg;
    return dat_ptr.*;
}

/// Write to IOAPIC Register (Indirect Access)
fn ioapicWrite(reg: u32, value: u32) void {
    const base = getVirtualAddress(IOAPIC_PHYS_BASE);
    const idx_ptr = @as(*volatile u32, @ptrFromInt(base + 0x00));
    const dat_ptr = @as(*volatile u32, @ptrFromInt(base + 0x10));

    idx_ptr.* = reg;
    dat_ptr.* = value;
}

const vmm = @import("../../kernel/memory/vmm.zig");

// ...

pub fn init() void {
    // 0. Map MMIO Regions via VMM
    // We map them to HHDM + PhysBase
    const lapic_virt = getVirtualAddress(LAPIC_PHYS_BASE);
    const ioapic_virt = getVirtualAddress(IOAPIC_PHYS_BASE);

    // Flags: Present | ReadWrite | CacheDisable (MMIO should not be cached)
    // Note: vmm.mapPage takes constants. Access them via vmm or hardcode?
    // Let's rely on VMM constants being private, we pass raw flags or add public flags to vmm?
    // vmm flags are private. Let's pass raw values or make them public?
    // vmm flags are private. I will update vmm to make flags public or magic number (PTE_PRESENT=1, RW=2, PCD=16).
    // Let's use magic numbers for now or update vmm.
    const PTE_PRESENT = 1;
    const PTE_RW = 2;
    const PTE_PCD = 16; // Cache Disable

    vmm.mapPage(lapic_virt, LAPIC_PHYS_BASE, PTE_PRESENT | PTE_RW | PTE_PCD, 0) catch {
        serial.err("APIC: Failed to map LAPIC Page!");
        while (true) {}
    };
    vmm.mapPage(ioapic_virt, IOAPIC_PHYS_BASE, PTE_PRESENT | PTE_RW | PTE_PCD, 0) catch {
        serial.err("APIC: Failed to map IOAPIC Page!");
        while (true) {}
    };

    // 1. Disable legacy PIC (mask all)
    // Even though we are switching to APIC, legacy PICs can still cause trouble if not silenced.
    io.outb(0xA1, 0xFF);
    io.outb(0x21, 0xFF);

    serial.debug("Disabling Legacy PIC...");

    // 2. Enable Local APIC
    // Set SVR (Spurious Interrupt Vector Register)
    // Bit 8 = Enable APIC
    // Bits 0-7 = Vector number for spurious interrupts (e.g., 0xFF)
    lapicWrite(LAPIC_SVR, 0x1FF); // Enable + Vector 255

    serial.info("Local APIC Initialized (SVR=0x1FF)");

    // 3. Initialize IOAPIC (Log ID/Version)
    const ver = ioapicRead(IOAPIC_VER);
    const count = (ver >> 16) & 0xFF; // Max Redirection Entry (Number of IRQs - 1)

    serial.info("IOAPIC Initialized");
    serial.debug("IOAPIC Version: ");
    serial.printHex(.debug, ver & 0xFF);
    serial.debug("IOAPIC Max Redirection Entries: ");
    serial.printHex(.debug, count);

    // Mask all IOAPIC Entries by default?
    // They usually come up masked, but good practice to clear them.
    // (omitted for brevity, we will just enable the ones we need)
}

/// Send End of Interrupt to Local APIC
pub fn sendEoi() void {
    lapicWrite(LAPIC_EOI, 0);
}

/// Enable a legacy IRQ (0-15) by mapping it to a CPU Vector via IOAPIC
pub fn enableIrq(irq: u8, vector: u8) void {
    // Redirection Table Entry (64-bit)
    // Low 32 bits:
    //   [0-7]   Vector
    //   [8-10]  Delivery Mode (000 = Fixed)
    //   [11]    Dest Mode (0 = Physical)
    //   [12]    Delivery Status (RO)
    //   [13]    Pin Polarity (0 = High Active)
    //   [14]    Remote IRR (RO)
    //   [15]    Trigger Mode (0 = Edge)
    //   [16]    Mask (0 = Unmasked, 1 = Masked)
    // High 32 bits:
    //   [56-63] Destination (APIC ID)

    const low_index = IOAPIC_RED_TBL + (irq * 2);
    const high_index = IOAPIC_RED_TBL + (irq * 2) + 1;

    // Target CPU APIC ID 0 (BSP)
    const high_val: u32 = 0 << 24;

    // Fixed mode, Physical, High Active, Edge, Unmasked, Vector
    const low_val: u32 = vector; // Rest are 0

    ioapicWrite(high_index, high_val);
    ioapicWrite(low_index, low_val);
}

// --- Unit Tests ---

test "APIC Constants" {
    try std.testing.expect(LAPIC_SVR == 0x00F0);
    try std.testing.expect(LAPIC_EOI == 0x00B0);
}

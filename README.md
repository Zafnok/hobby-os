# Next-Gen PKS/SASOS Operating System

This operating system represents a fundamental shift in kernel architecture, moving away from traditional ring-based isolation (Ring 0/3) towards a hardware-enforced, single address space model using CPU Protection Keys.

## Core Architecture

### 🛡️ Hardware-Enforced Safety (PKS & SASOS)
Instead of relying on the traditional localized memory isolation provided by paging levels (Ring 0 vs Ring 3), this OS implements a **Single Address Space Operating System (SASOS)**. Memory safety and isolation are enforced directly at the CPU layer using **Protection Keys for Supervisor (PKS)**.

*   **Zero-Cost Switching**: Eliminates the overhead of `cr3` switching and TLB flushes associated with traditional context switches.
*   **Granular Protection**: Domains are isolated by protection keys rather than virtual address spaces.

### ⚡ Async-Only I/O
The I/O subsystem is designed to be fully asynchronous from the ground up, maximizing throughput and non-blocking performance.

*   **No Blocking Syscalls**: All I/O operations are non-blocking.
*   **Legacy Compatibility**: A compatibility shim is provided to enable legacy synchronous I/O applications to run in a mimicked mode, bridging the gap without compromising the core architecture.

### ⏱️ Tickless Scheduling
We have abandoned the traditional 1000Hz polling interrupt. The scheduler operates in a **tickless** (dynamic tick) mode.

*   **Energy Efficiency**: The CPU wakes only when there is work to do.
*   **Precision**: Scheduling events are driven by precise hardware timers or interrupt events rather than arbitrary polling intervals.

## Development Requirements

This project has strict versioning requirements to ensure architectural stability.

| Tool | Version | Requirement |
| :--- | :--- | :--- |
| **Zig** | `0.15.2` | **Strict**. Do not use older/newer syntax. |
| **Limine** | `10.6.3` | **Strict**. |

**Core Constraints:**
*   **Architecture**: Single Address Space Operating System (SASOS) using PKS.
*   **I/O Model**: Fully Asynchronous.
*   **Scheduling**: Tickless/Dynamic.

## Feature Roadmap

- [x] **PMM (Physical Memory Manager)**: Basic page allocation.
- [x] **VMM (Virtual Memory Manager)**: Higher Half Direct Map, Page Tables.
- [x] **Framebuffer**: Basic drawing primitives (points, rects, fill).
- [x] **Font Rendering**: 8x8 Bitmap font (ASCII 32-127).
- [x] **Keyboard**: Basic Scancode Set 1 polling.
- [/] **Shift Key Support**: (In Progress) Capital letters & symbols.
- [ ] **APIC**: Modern interrupt controller (Replacing legacy PIC).
- [ ] **ACPI / MADT Parsing**: Properly detecting hardware configuration (APIC bases, multiple cores).
- [ ] **Heap Allocator**: Kernel heap support.
- [ ] **File System**: Basic read-only FS support.
- [x] **ELF Loader**: Loading executable programs (`src/loaders/elf.zig`).
- [x] **Interactive Shell**: Basic kernel shell (`src/demos/shell.zig`).
- [ ] **User Mode (Ring 3)**: Switching to/from userspace.
- [ ] **Minecraft**: Download and boot the jar (The Ultimate Goal).

## Hardware Compatibility

CRITICAL: This OS relies on server-grade CPU instructions. Consumer hardware as of 2026 is **largely unsupported**.

### Intel
*   **Supported**: **Sapphire Rapids** (4th Gen Xeon Scalable), **Emerald Rapids**, **Granite Rapids** and later server chips.
*   **UNSUPPORTED Consumer Lines**: Core i9/i7/i5 (12th-14th Gen), **Core Ultra Series 1 & 2** (Meteor Lake, Arrow Lake, Lunar Lake). These chips support User keys (PKU) but **LACK** Supervisor keys (PKS).

### AMD
*   **Supported**: Future high-end EPYC architectures (check specific generation specs for Supervisor Key support).
*   **UNSUPPORTED (Current)**: **Zen 3, Zen 4, and Zen 5** (Ryzen 5000-9000, EPYC Milan/Genoa/Turin). These architectures support User keys (PKU) but do not historically implement the Supervisor equivalent required for this kernel.

### Apple Silicon / ARM
*   **Supported**: Future chips implementing **ARMv9.4+** (Permission Overlay Extensions - POE).
*   **UNSUPPORTED**: **M1, M2, M3, M4, and M5**.
    *   Note: **M5** is based on **ARMv9.2-A**, which predates the required POE feature set. Support is expected likely in the M6 or later generation.

## QEMU Emulation

Since PKS hardware is rare in consumer devices, you can develop using QEMU's TCG emulation.

**Required Flags:**
You must manually enable the `pks` CPU flag or use a CPU model that implies it (like `SapphireRapids`).

```bash
# Recommended: Use 'max' model with explicit PKS enabled
qemu-system-x86_64 -cpu max,+pks -M q35 ...

# Alternative: Emulate a specific supported server chip
qemu-system-x86_64 -cpu SapphireRapids ...
```

**Verify Support:**
If the kernel panics early with a "PKS not supported" message, double-check that you are NOT using KVM (`-enable-kvm` or `-accel kvm`) unless your host CPU actually supports PKS (Sapphire Rapids+). You must use software emulation (TCG) on unsupported host hardware.

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

## Kernel Table Architecture (SASOS Syscall Mechanism)

### The Two-Layer Wrapper System

Our OS uses a **kernel table** of function pointers as the syscall mechanism, replacing traditional `syscall` instructions. This requires wrappers on both sides:

**Kernel-Side Wrappers** (`src/kernel/table.zig`):
- Run in **kernel-protected memory** with PKS privileges
- Bridge kernel internals → C ABI contract
- Example: `framebuffer.drawRect()` (takes framebuffer pointer, uses `u64`) → `kernelDrawRect()` (hides pointer, uses `u32`)

**User-Side Wrappers** (`src/user/lib.zig`):
- Run in **userspace** (part of the user program)
- Bridge C ABI contract → idiomatic Zig
- Example: `kernel_table.poll_key()` (returns `0 | char`) → `getKey()` (returns `?u8`)

### Why Can't Userspace Call Drivers Directly?

**The Answer: PKS Memory Isolation**

In traditional OS (Ring 0/3):
- Kernel and userspace have **separate address spaces**
- Userspace can't call kernel because kernel code doesn't exist in userspace page tables
- Use `syscall` instruction to switch address spaces

In our SASOS with PKS:
- Kernel and userspace **share the same address space** (everything mapped)
- BUT kernel memory is **protected by Protection Keys** (PKS)
- Userspace can see addresses but **cannot access them** - CPU blocks with Page Fault

**The kernel table is the bridge:**
- Function pointers point to kernel wrapper functions
- Wrappers run with **kernel privileges** (PKS allows them to access kernel memory)
- When userspace calls through a function pointer, CPU transitions to kernel privilege
- Wrappers safely access kernel drivers and hardware

**The call flow:**
```
Snake Game (userspace)
  ↓ calls getKey()                   // User wrapper (Zig convenience)
  ↓ accesses kernel_table pointer    // Shared address space (SASOS)
  ↓ calls .poll_key()                // Function pointer in table
  ↓ CPU transitions to kernel        // PKS allows kernel code execution
  ↓ executes kernelPollKey()         // Kernel wrapper (has PKS privileges)
  ↓ calls keyboard.pop()             // Kernel driver (accesses protected memory)
  ↓ returns to userspace             // CPU transitions back
```

Without kernel wrappers, we'd have to either:
- Put drivers in unprotected memory (defeats PKS isolation)
- Give userspace direct hardware access (unsafe, defeats the entire OS)

**The kernel table + wrappers is our SASOS syscall mechanism** - it replaces traditional `syscall` instructions!

## Architectural FAQ

### Why does the kernel table wrapper have different signatures than the underlying drivers?

**Q:** Why does `kernelDrawRect()` take `u32` parameters when `framebuffer.drawRect()` uses `u64`?

**A:** The kernel table defines the **userspace API**, while drivers use types that match hardware:
- **Limine framebuffer protocol** uses `u64` for width/height (matching the bootloader spec)
- **Userspace API** uses `u32` (more practical - no framebuffer is 4 billion pixels wide)
- The wrapper also **hides framebuffer pointers** from userspace (SASOS design - userspace doesn't manage hardware resources directly)

### Why don't we use the VMM more?

**Q:** If heap and kernel table don't use VMM, when do we actually use it?

**A:** In SASOS, VMM has a **minimal role** compared to traditional OS:

**Traditional OS:**
- Creates separate address spaces for each process
- Constantly maps/unmaps pages as processes spawn/die
- Heavy VMM usage for every memory operation

**SASOS (our OS):**
- **One-time setup**: Creates page tables, maps HHDM, maps kernel (during `vmm.init()`)
- **Special mappings only**: MMIO regions (APIC), ELF segments with specific permissions, PKS-protected regions
- **Most allocations use PMM + HHDM directly**: No VMM needed because everything shares one address space

**Why it works:** PKS (Protection Keys) provides isolation without separate page tables. Physical pages from PMM are already accessible via HHDM.

### Why can't `serial.info()` be used for userspace logging?

**Q:** Why create `serial.logRaw()` when `serial.info()` already exists?

**A:** Userspace needs **complete output control**:

```zig
// With serial.info():
log("Score: ");  // Outputs: [INFO] Score: \n
log("42");       // Outputs: [INFO] 42\n
// Result: Two lines with prefixes

// With serial.logRaw():
log("Score: ");  // Outputs: Score: 
log("42");       // Outputs: 42
// Result: "Score: 42" on one line, no prefixes
```

Kernel functions add `[INFO]` tags and newlines. Games and userspace programs need raw output for progress bars, scoreboards, animations, etc.

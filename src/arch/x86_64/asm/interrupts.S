/*
 * src/arch/x86_64/asm/interrupts.S
 * Assembly trampolines for Interrupt Service Routines (ISRs)
 */

.code64
.section .text

/*
 * Macro for exceptions that DO NOT push an error code.
 * We push 0 as a dummy error code to keep the stack frame consistent.
 */
.macro ISR_NO_ERRCODE index
.global isr_stub_\index
isr_stub_\index:
    pushq $0                /* Dummy error code */
    pushq $\index           /* Interrupt number */
    jmp isr_common_stub
.endm

/*
 * Macro for exceptions that DO push an error code.
 * The CPU has already pushed the error code, so we just push the index.
 */
.macro ISR_ERRCODE index
.global isr_stub_\index
isr_stub_\index:
    pushq $\index           /* Interrupt number */
    jmp isr_common_stub
.endm

/*
 * Common Stub: Saves state, calls Zig, restores state.
 */
isr_common_stub:
    /* 1. Save General Purpose Registers */
    pushq %r15
    pushq %r14
    pushq %r13
    pushq %r12
    pushq %r11
    pushq %r10
    pushq %r9
    pushq %r8
    pushq %rbp
    pushq %rdi
    pushq %rsi
    pushq %rdx
    pushq %rcx
    pushq %rbx
    pushq %rax

    /* 2. Prepare Argument for Zig Function
     * The stack pointer (%rsp) points to the InterruptFrame structure
     * because we just pushed all the registers that match the struct layout.
     * Zig fn signature: fn handleInterrupt(frame: *InterruptFrame)
     * So we move %rsp into %rdi (1st argument in System V AMD64 ABI).
     */
    movq %rsp, %rdi

    /* 3. Call Zig Handler */
    call handleInterrupt

    /* 4. Restore Registers */
    popq %rax
    popq %rbx
    popq %rcx
    popq %rdx
    popq %rsi
    popq %rdi
    popq %rbp
    popq %r8
    popq %r9
    popq %r10
    popq %r11
    popq %r12
    popq %r13
    popq %r14
    popq %r15

    /* 5. Clean up stack (Error Code + Interrupt Number) */
    addq $16, %rsp

    /* 6. Return from Interrupt */
    iretq

/*
 * Define Stubs for Exceptions 0-31
 */
ISR_NO_ERRCODE 0  /* Divide by Zero */
ISR_NO_ERRCODE 1  /* Debug */
ISR_NO_ERRCODE 2  /* NMI */
ISR_NO_ERRCODE 3  /* Breakpoint */
ISR_NO_ERRCODE 4  /* Overflow */
ISR_NO_ERRCODE 5  /* Bound Range */
ISR_NO_ERRCODE 6  /* Invalid Opcode */
ISR_NO_ERRCODE 7  /* Device Not Available */
ISR_ERRCODE    8  /* Double Fault */
ISR_NO_ERRCODE 9  /* Coprocessor Segment Overrun (Deprecated) */
ISR_ERRCODE    10 /* Invalid TSS */
ISR_ERRCODE    11 /* Segment Not Present */
ISR_ERRCODE    12 /* Stack-Segment Fault */
ISR_ERRCODE    13 /* General Protection Fault */
ISR_ERRCODE    14 /* Page Fault */
ISR_NO_ERRCODE 15 /* Reserved */
ISR_NO_ERRCODE 16 /* x87 Floating Point Exception */
ISR_ERRCODE    17 /* Alignment Check */
ISR_NO_ERRCODE 18 /* Machine Check */
ISR_NO_ERRCODE 19 /* SIMD Floating Point Exception */
ISR_NO_ERRCODE 20 /* Virtualization Exception */
ISR_NO_ERRCODE 21 /* Control Protection Exception */
ISR_NO_ERRCODE 22 /* Reserved */
ISR_NO_ERRCODE 23 /* Reserved */
ISR_NO_ERRCODE 24 /* Reserved */
ISR_NO_ERRCODE 25 /* Reserved */
ISR_NO_ERRCODE 26 /* Reserved */
ISR_NO_ERRCODE 27 /* Reserved */
ISR_NO_ERRCODE 28 /* Reserved */
ISR_NO_ERRCODE 29 /* Reserved */
ISR_ERRCODE    30 /* Security Exception */
ISR_NO_ERRCODE 31 /* Reserved */

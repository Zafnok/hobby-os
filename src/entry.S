/* src/entry.S */
.section .bss
.align 16
stack_bottom:
.skip 16384
stack_top:

.section .text
.global _start
_start:
    /* 1. Setup Stack */
    mov $stack_top, %rsp

    /* 2. Enable SSE */
    mov %cr0, %rax
    and $0xfffb, %ax
    or  $0x2, %ax
    mov %rax, %cr0

    mov %cr4, %rax
    or  $0x600, %ax  /* OSFXSR | OSXMMEXCPT */
    mov %rax, %cr4

    /* 3. Enter Kernel */
    call kmain

    cli
1:  hlt
    jmp 1b

.global _start

.section .text
_start:
    /* Stick 0xDEADBEEF in RAX to signal success if inspected */
    mov $0xDEADBEEF, %rax
    
    /* Infinite Loop */
loop:
    hlt
    jmp loop

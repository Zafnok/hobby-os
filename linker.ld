/* linker.ld */
ENTRY(_start)

SECTIONS
{
    . = 0xffffffff80000000;

    .limine_reqs : {
        KEEP(*(.limine_reqs))
    }

    . = ALIGN(4096);

    .text : {
        *(.text .text.*)
    }

    . = ALIGN(4096);

    .rodata : {
        *(.rodata .rodata.*)
    }

    . = ALIGN(4096);

    .data : {
        *(.data .data.*)
    }

    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    }

    /DISCARD/ : {
        *(.eh_frame)
        *(.note .note.*)
    }
}
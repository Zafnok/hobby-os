/* linker.ld */
ENTRY(_start)

PHDRS
{
    requests PT_LOAD FLAGS((1 << 1) | (1 << 2)) ; /* Read + Write */
    text     PT_LOAD FLAGS((1 << 0) | (1 << 2)) ; /* Read + Execute */
    rodata   PT_LOAD FLAGS((1 << 2)) ;            /* Read Only */
    data     PT_LOAD FLAGS((1 << 1) | (1 << 2)) ; /* Read + Write */
}

SECTIONS
{
    . = 0xffffffff80000000;

    .limine_reqs : AT(ADDR(.limine_reqs) - 0xffffffff80000000 + 0x200000) {
        KEEP(*(.limine_reqs))
    } :requests

    . = ALIGN(0x1000);

    .text : AT(ADDR(.text) - 0xffffffff80000000 + 0x200000) {
        *(.text .text.*)
    } :text

    . = ALIGN(0x1000);

    .rodata : AT(ADDR(.rodata) - 0xffffffff80000000 + 0x200000) {
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(0x1000);

    .data : AT(ADDR(.data) - 0xffffffff80000000 + 0x200000) {
        *(.data .data.*)
    } :data

    .bss : AT(ADDR(.bss) - 0xffffffff80000000 + 0x200000) {
        *(.bss .bss.*)
        *(COMMON)
    } :data

    /DISCARD/ : {
        *(.eh_frame)
        *(.note .note.*)
    }
}
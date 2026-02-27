ENTRY(_start)

PHYS = 0x00100000;

PHDRS
{
    bootdata    PT_LOAD FLAGS(0x6); /* RW */
    boottext    PT_LOAD FLAGS(0x5); /* RX */
    text        PT_LOAD FLAGS(0x5); /* RX */
    ro          PT_LOAD FLAGS(0x4); /* R */
    data        PT_LOAD FLAGS(0x6); /* RW */
    bss         PT_LOAD FLAGS(0x6); /* RW */
}

SECTIONS
{
    . = PHYS;

    .multiboot.data ALIGN(8) :
    {
        KEEP(*(.multiboot.data))
    }                           :bootdata

    .multiboot.text ALIGN(4) :
    {
        KEEP(*(.multiboot.text))
    }                           :boottext

    _kernel_start = .;

    .text ALIGN(4K) :
    {
        *(.text .text.*)
    }                           :text

    .rodata ALIGN(4K) :
    {
        *(.rodata .rodata.*)
        *(.eh_frame_hdr)
        *(.eh_frame)
    }                           :ro

    .data ALIGN(4K) :
    {
        *(.data .data.*)
    }                           :data

    .bss ALIGN(4K) (NOLOAD) :
    {
        *(COMMON)
        *(.bss .bss.*)
        *(.bootstrap_stack)
    }                           :bss

    _kernel_end = .;

    /DISCARD/ : {
        *(.comment)
        *(.note*)
    }
}

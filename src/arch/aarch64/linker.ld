ENTRY(_start)

SECTIONS
{
    . = 0x40080000;

    _kernel_start = .;

    .text ALIGN(4K) :
    {
        KEEP(*(.text._start))
        *(.text .text.*)
    }

    .rodata ALIGN(4K) :
    {
        *(.rodata .rodata.*)
        *(.eh_frame_hdr)
        *(.eh_frame)
    }

    .data ALIGN(4K) :
    {
        *(.data .data.*)
    }

    __bss_start = .;
    .bss ALIGN(64K) (NOLOAD) :
    {
        *(COMMON)
        *(.bss .bss.*)
    }
    __bss_end = .;

    _kernel_end = .;

    /DISCARD/ : {
        *(.comment)
        *(.note*)
    }
}

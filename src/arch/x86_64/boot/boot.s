.code32
# Multiboot2 header constants
.set MULTIBOOT2_MAGIC,           0xe85250d6
.set MULTIBOOT2_ARCHITECTURE,    0          # i386 protected mode
.set MULTIBOOT2_HEADER_LENGTH,   (multiboot2_header_end - multiboot2_header_start)
.set MULTIBOOT2_CHECKSUM,        -(MULTIBOOT2_MAGIC + MULTIBOOT2_ARCHITECTURE + MULTIBOOT2_HEADER_LENGTH)

# Video mode preferences  
.set WIDTH,             0     # desired width
.set HEIGHT,            0     # desired height
.set DEPTH,             32       # desired bits per pixel

# Tag types
.set MULTIBOOT2_TAG_END,              0
.set MULTIBOOT2_TAG_INFORMATION,      1
.set MULTIBOOT2_TAG_FRAMEBUFFER,      5

# Tag flags
.set MULTIBOOT2_TAG_OPTIONAL,         1

# Declare a multiboot2 header that marks the program as a kernel
.section .multiboot.data, "aw"
    .align 8
multiboot2_header_start:
    # Multiboot2 header
    .long MULTIBOOT2_MAGIC
    .long MULTIBOOT2_ARCHITECTURE  
    .long MULTIBOOT2_HEADER_LENGTH
    .long MULTIBOOT2_CHECKSUM
    
    # Information request tag (equivalent to MEMINFO flag)
    .align 8
information_tag_start:
    .word MULTIBOOT2_TAG_INFORMATION    # type
    .word 0                             # flags (required)
    .long (information_tag_end - information_tag_start)  # size
    .long 4                             # memory map request
    .long 6                             # memory info request
information_tag_end:
    
    # Framebuffer tag (equivalent to VIDEO flag and mode settings)
    .align 8
framebuffer_tag_start:
    .word MULTIBOOT2_TAG_FRAMEBUFFER    # type
    .word MULTIBOOT2_TAG_OPTIONAL       # flags (optional)
    .long (framebuffer_tag_end - framebuffer_tag_start)  # size
    .long WIDTH                         # width
    .long HEIGHT                        # height
    .long DEPTH                         # depth (bits per pixel)
framebuffer_tag_end:
    
    # End tag
    .align 8
    .word MULTIBOOT2_TAG_END            # type
    .word 0                             # flags
    .long 8                             # size
    
multiboot2_header_end:

# Allocate the initial stack.
.section .bootstrap_stack, "aw", @nobits
.align 16
.globl stack_bottom
stack_bottom:
.skip 4096 * 1024
.globl stack_top
stack_top:

# Preallocate pages used for paging. Don't hard-code addresses and assume they
# are available, as the bootloader might have loaded its multiboot structures or
# modules there. This lets the bootloader know it must avoid the addresses.
.section .bss, "aw", @nobits
	.align 4096
.global boot_pml4
boot_pml4:
    .skip 4096
boot_pdpt:
    .skip 4096
boot_pd:
    .skip 4096

# The kernel entry point.
.section .multiboot.text, "a"

.global _start
.type _start, @function
_start:
    cli

    # Save multiboot values
    movl %eax, %esi             # esi = magic
    movl %ebx, %edi             # edi = multiboot info address

    # ------------------------------------------------------------------
    # Build identity-map page tables (first 1GB)
    # ------------------------------------------------------------------

    # Zero all page table pages (3 pages * 4096 bytes)
    movl $(boot_pml4), %eax
    movl $(4096 * 3 / 4), %ecx
    xorl %edx, %edx
.zero_loop:
    movl %edx, (%eax)
    addl $4, %eax
    decl %ecx
    jnz .zero_loop

    # PML4[0] -> boot_pdpt (identity map)
    movl $(boot_pdpt + 0x03), %eax      # Present + Writable
    movl %eax, (boot_pml4)

    # PDPT[0] -> boot_pd
    movl $(boot_pd + 0x03), %eax
    movl %eax, (boot_pdpt)

    # Fill PD with 512 x 2MB huge pages (maps 0..1GB)
    movl $(boot_pd), %eax
    movl $0x00000083, %ebx      # Present + Writable + Huge(2MB)
    movl $512, %ecx
.fill_pd:
    movl %ebx, (%eax)
    movl $0, 4(%eax)
    addl $0x00200000, %ebx
    addl $8, %eax
    decl %ecx
    jnz .fill_pd

    # ------------------------------------------------------------------
    # Switch to long mode
    # ------------------------------------------------------------------

    # Load PML4 into CR3
    movl $(boot_pml4), %eax
    movl %eax, %cr3

    # Enable PAE in CR4
    movl %cr4, %eax
    orl $(1 << 5), %eax
    movl %eax, %cr4

    # Enable Long Mode in EFER MSR (0xC0000080)
    movl $0xC0000080, %ecx
    rdmsr
    orl $(1 << 8), %eax         # LME bit
    wrmsr

    # Enable paging in CR0
    movl %cr0, %eax
    orl $(1 << 31), %eax
    movl %eax, %cr0

    # Load temporary 64-bit GDT and jump to long mode
    lgdt (boot_gdt64_ptr)
    ljmp $0x08, $long_mode_start

# ============================================================================
# Temporary 64-bit GDT
# ============================================================================
.align 16
boot_gdt64:
    .quad 0x0000000000000000    # Null
    .quad 0x00AF9A000000FFFF    # Code: 64-bit, DPL0, Execute/Read
    .quad 0x00AF92000000FFFF    # Data: 64-bit, DPL0, Read/Write
boot_gdt64_end:

boot_gdt64_ptr:
    .word boot_gdt64_end - boot_gdt64 - 1
    .long boot_gdt64

# ============================================================================
# 64-bit entry
# ============================================================================
.code64
.section .text
.global long_mode_start
long_mode_start:
    # Reload segment registers with 64-bit data segment
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss

    # Set up stack
    movabsq $stack_top, %rsp
    xorq %rbp, %rbp

    # Prepare kernel_main arguments (System V AMD64 ABI):
    #   rdi = first arg  = multiboot2 magic
    #   rsi = second arg = multiboot2 info physical address
    # We saved: esi = magic, edi = info_addr at _start
    movl %esi, %eax             # eax = magic
    movl %edi, %esi             # rsi = info address (second arg)
    movl %eax, %edi             # rdi = magic (first arg)

    call kernel_main

    # Halt if kernel returns
    cli
1:  hlt
    jmp 1b

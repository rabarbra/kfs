// AArch64 boot code for QEMU virt machine
// Entry point: _start
// The kernel is loaded at 0x40080000 by QEMU -kernel
// DTB pointer is passed in x0 by the bootloader/QEMU
//
// We must enable the MMU with an identity map so that RAM is marked as
// Normal memory (allowing unaligned accesses). Without the MMU, all
// memory is treated as Device-nGnRnE which faults on unaligned access.

// MAIR_EL1 attribute indices
.set MAIR_DEVICE_nGnRnE, 0x00   // index 0
.set MAIR_NORMAL_NC,     0x44   // index 1: Normal, Non-Cacheable

// TCR_EL1 configuration
// T0SZ=25 means 39-bit VA (512GB), 4K granule
.set TCR_T0SZ,   25
.set TCR_TG0_4K, (0 << 14)
.set TCR_IPS_40, (2 << 32)      // 40-bit PA (1TB)

// Block descriptor bits
.set TD_VALID,     (1 << 0)
.set TD_BLOCK,     0            // block entry (bit 1 = 0 for L1/L2 block)
.set TD_TABLE,     (1 << 1)    // table entry (bit 1 = 1)
.set TD_AF,        (1 << 10)   // Access Flag
.set TD_ATTR_DEV,  (0 << 2)    // AttrIndx = 0 (Device)
.set TD_ATTR_NORM, (1 << 2)    // AttrIndx = 1 (Normal)
.set TD_ISH,       (3 << 8)    // Inner Shareable

.section .text._start
.global _start
_start:
    // x0 contains DTB address from QEMU (we ignore it for now)
    // Mask all exceptions
    msr daifset, #0xf

    // Read current exception level
    mrs x1, CurrentEL
    lsr x1, x1, #2
    cmp x1, #2
    b.eq from_el2

    // Already at EL1, just continue
    b setup_mmu

from_el2:
    // Configure EL1 before dropping down
    // Set EL1 to AArch64
    mov x0, #(1 << 31)     // RW bit = AArch64 for EL1
    msr hcr_el2, x0

    // Set up SCTLR_EL1 to a known state (MMU off)
    mov x0, #0
    msr sctlr_el1, x0

    // Set up SPSR_EL2 to return to EL1h
    mov x0, #0x3c5         // DAIF masked, EL1h (SP_EL1)
    msr spsr_el2, x0

    // Set return address to setup_mmu
    adr x0, setup_mmu
    msr elr_el2, x0

    eret

setup_mmu:
    // ---------------------------------------------------------------
    // Set up MAIR_EL1: attr[0]=Device-nGnRnE, attr[1]=Normal Non-Cacheable
    // ---------------------------------------------------------------
    ldr x0, =((MAIR_NORMAL_NC << 8) | MAIR_DEVICE_nGnRnE)
    msr mair_el1, x0

    // ---------------------------------------------------------------
    // Zero the page tables (2 pages = 8192 bytes)
    // ---------------------------------------------------------------
    ldr x0, =boot_pgd
    mov x1, #(4096 * 2 / 8)   // number of 8-byte entries to zero
1:  str xzr, [x0], #8
    subs x1, x1, #1
    b.ne 1b

    // ---------------------------------------------------------------
    // Build identity-map page tables
    //
    // With 4K granule + 39-bit VA (T0SZ=25):
    //   L0 (PGD): not used for 39-bit VA, start at L1
    //   L1: each entry covers 1GB  (bits [38:30])
    //   L2: each entry covers 2MB  (bits [29:21]) — not used here
    //
    // L1 table at boot_pgd:
    //   [0] = 1GB block at 0x0000_0000 — Device memory (UART, GIC, etc.)
    //   [1] = 1GB block at 0x4000_0000 — Normal memory (RAM where kernel lives)
    // ---------------------------------------------------------------
    ldr x0, =boot_pgd

    // Entry 0: 0x0000_0000..0x3FFF_FFFF = Device memory (1GB block)
    ldr x1, =(0x00000000 | TD_VALID | TD_AF | TD_ATTR_DEV)
    str x1, [x0, #0]

    // Entry 1: 0x4000_0000..0x7FFF_FFFF = Normal memory (1GB block)
    ldr x1, =(0x40000000 | TD_VALID | TD_AF | TD_ATTR_NORM | TD_ISH)
    str x1, [x0, #8]

    // ---------------------------------------------------------------
    // Set TTBR0_EL1 to point to our L1 table
    // ---------------------------------------------------------------
    ldr x0, =boot_pgd
    msr ttbr0_el1, x0

    // ---------------------------------------------------------------
    // Configure TCR_EL1
    // T0SZ=25 (39-bit VA), TG0=4K, IPS=40-bit
    // ---------------------------------------------------------------
    ldr x0, =(TCR_T0SZ | TCR_TG0_4K | TCR_IPS_40)
    msr tcr_el1, x0

    // Barrier before enabling MMU
    isb

    // ---------------------------------------------------------------
    // Enable the MMU
    // SCTLR_EL1: M=1 (MMU on), A=0 (no alignment check), C=0, I=0
    // ---------------------------------------------------------------
    mrs x0, sctlr_el1
    orr x0, x0, #1          // Set M bit (MMU enable)
    msr sctlr_el1, x0
    isb

setup_stack:
    // Set up the stack pointer (grows downward)
    ldr x0, =stack_top
    mov sp, x0

    // Zero the BSS section
    ldr x0, =__bss_start
    ldr x1, =__bss_end
zero_bss:
    cmp x0, x1
    b.ge bss_done
    str xzr, [x0], #8
    b zero_bss
bss_done:

    // Call kernel_main(0x36d76289, 0)
    // Pass multiboot2 magic so kernel_main's magic check passes
    // Second arg is 0 (no multiboot address on aarch64)
    ldr x0, =0x36d76289
    mov x1, #0
    bl kernel_main

    // If kernel_main returns, hang
halt:
    wfe
    b halt

// ---------------------------------------------------------------
// Page tables in BSS (zeroed by boot code above, NOT by BSS zero
// loop which runs after MMU is on — so these must be before BSS)
// ---------------------------------------------------------------
.section .data
.align 12   // 4K aligned
.global boot_pgd
boot_pgd:
    .skip 4096      // L1 table (512 entries, only first 2 used)

// Stack allocation
.section .bss
.align 16
.global stack_bottom
stack_bottom:
    .skip 4096 * 64    // 256KB stack
.global stack_top
stack_top:

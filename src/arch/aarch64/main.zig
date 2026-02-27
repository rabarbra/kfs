const std = @import("std");
const krn = @import("kernel");

const UART_BASE: usize = 0x0900_0000;

// PL011 register offsets
const UART_DR:      usize = 0x000;  // Data Register
const UART_FR:      usize = 0x018;  // Flag Register
const UART_FR_TXFF: u32 = (1 << 5); // Transmit FIFO full
const UART_FR_RXFE: u32 = (1 << 4); // Receive FIFO empty

fn mmio_write(reg: usize, val: u32) void {
    const ptr: *volatile u32 = @ptrFromInt(reg);
    ptr.* = val;
}

fn mmio_read(reg: usize) u32 {
    const ptr: *volatile u32 = @ptrFromInt(reg);
    return ptr.*;
}

fn uart_putc(c: u8) void {
    // Wait until transmit FIFO is not full
    while (mmio_read(UART_BASE + UART_FR) & UART_FR_TXFF != 0) {}
    mmio_write(UART_BASE + UART_DR, @as(u32, c));
}

fn uart_getc() ?u8 {
    if (mmio_read(UART_BASE + UART_FR) & UART_FR_RXFE != 0) {
        return null;
    }
    return @truncate(mmio_read(UART_BASE + UART_DR));
}

// ============================================================================
// I/O interface (memory-mapped on aarch64, no port I/O)
// We map port 0x3F8 (COM1) operations to PL011 UART for serial driver compat
// ============================================================================
pub const io = struct {
    pub fn inb(port: u16) u8 {
        // Map COM1 serial port reads to UART
        if (port == 0x3F8) {
            return uart_getc() orelse 0;
        }
        if (port == 0x3FD) {
            // Line Status Register: always report TX empty, ready
            return 0x60;
        }
        return 0;
    }

    pub fn inw(_: u16) u16 {
        return 0;
    }

    pub fn inl(_: u16) u32 {
        return 0;
    }

    pub fn outb(port: u16, value: u8) void {
        // Map COM1 serial port writes to UART
        if (port == 0x3F8) {
            uart_putc(value);
        }
    }

    pub fn outw(_: u16, _: u16) void {}

    pub fn outl(_: u16, _: u32) void {}
};

pub const system = struct {
    pub fn halt() noreturn {
        while (true) {
            asm volatile ("wfe");
        }
    }

    pub fn enableWriteProtect() void {}
};

pub const gdt = struct {
    pub fn gdtInit() void {}
};

pub const multiboot = struct {
    pub const Header = struct {
        total_size: u32,
        reserved: u32,
    };

    pub const Tag = struct {
        type: u32,
        size: u32,
    };

    pub const MemMapEntry = struct {
        base_addr: u64,
        length: u64,
        type: u32,
        reserved: u32,
    };

    pub const TagMemoryMap = struct {
        type: u32 = 6,
        size: u32,
        entry_size: u32,
        entry_version: u32,

        pub fn getMemMapEntries(_: *TagMemoryMap) [*]MemMapEntry {
            return @ptrFromInt(0xA000_0000);
        }
    };

    pub const TagFrameBufferInfo = struct {
        type: u32 = 8,
        size: u32,
        addr: u64,
        pitch: u32,
        width: u32,
        height: u32,
        bpp: u8,
        fb_type: u8,
        reserved: u8,
    };

    pub const TagELFSymbols = struct {
        type: u32 = 9,
        size: u32,
        num: u16,
        entsize: u16,
        shndx: u16,
        reserved: u16,

        pub fn getSectionHeaders(_: *TagELFSymbols) [*]std.elf.Elf32_Shdr {
            return @ptrFromInt(0xA000_0000);
        }
    };

    pub const Multiboot = struct {
        addr: usize,
        header: *Header,
        curr_tag: ?*Tag = null,
        tag_addresses: [22]u32 = .{0} ** 22,

        pub fn init(addr: usize) Multiboot {
            return Multiboot{
                .addr = addr,
                .header = @ptrFromInt(if (addr == 0) 0xDEAD_0000 else addr),
            };
        }

        pub fn nextTag(self: *Multiboot) ?*Tag {
            _ = self;
            return null;
        }

        pub fn getTag(_: *Multiboot, comptime T: type) ?*T {
            return null;
        }

        pub fn relocate(_: *Multiboot, _: usize) usize {
            return 0;
        }
    };
};

pub const vmm = struct {
    pub const VASpair = struct {
        virt: usize = 0,
        phys: usize = 0,
    };
    pub const PagingFlags = packed struct {
        present: bool = true,
        writable: bool = true,
        user: bool = false,
        write_through: bool = false,
        cache_disable: bool = false,
        accessed: bool = false,
        dirty: bool = false,
        huge_page: bool = false,
        global: bool = false,
        available: u3 = 0x000,
    };
    pub const VMM = struct {
        pmm: *pmm.PMM,
        pub fn findFreeSpace(self: *VMM, num_pages: usize, from_addr: usize, to_addr: usize, user: bool) usize {
            _ = self;
            _ = num_pages;
            _ = from_addr;
            _ = to_addr;
            _ = user;
            return 0;
        }

        pub fn mapPage(_: *VMM, _: usize, _: usize, _: PagingFlags) void {}
        pub fn unmapPage(_: *VMM, _: usize, _: bool) void {}
        pub fn releaseArea(_: *VMM, _: usize, _: usize, _: krn.mm.MAP_TYPE) void {}
        pub fn init(_pmm: *pmm.PMM) VMM {
            return VMM{
                .pmm = _pmm,
            };
        }
    };

    pub const initial_page_dir: usize = 0;
};

pub const pmm = struct {
    pub const PMM = struct {
        free_area: []u32 = &.{},
        index: u32 = 0,
        size: u64 = 0,
        begin: u32 = 0,
        end: u32 = 0,

        pub fn init(_: usize, _: usize) PMM {
            return PMM{};
        }
        pub fn allocPage(_: *PMM) usize {
            return 0;
        }
        pub fn allocPages(_: *PMM, _: usize) usize {
            return 0;
        }
        pub fn freePage(_: *PMM, _: usize) void {}
    };
};

pub const idt = struct {
    pub fn idtInit() void {}
    pub const KERNEL_CODE_SEGMENT = 0;
    pub const KERNEL_DATA_SEGMENT = 0;
    pub fn switchTo(_: *krn.task.Task, _: *krn.task.Task, _: *Regs) *Regs {
        return &krn.task.initial_task.regs;
    }
    pub fn goUserspace() void {}
};

pub const fpu = struct {
    pub const FPUState = extern struct {
        raw: [512 + 15]u8 = .{0} ** (512 + 15),

        pub inline fn ptrAligned(self: *FPUState) *align(16) [512]u8 {
            const aligned = (@intFromPtr(&self.raw) + 15) & ~@as(usize, 15);
            return @ptrFromInt(aligned);
        }

        pub inline fn constPtrAligned(self: *const FPUState) *align(16) const [512]u8 {
            const aligned = (@intFromPtr(&self.raw) + 15) & ~@as(usize, 15);
            return @ptrFromInt(aligned);
        }
    };

    pub fn initFPU() void {
        // NEON/VFP is enabled by default configuration on aarch64 QEMU
    }

    pub fn saveFPUState(_: *FPUState) void {}
    pub fn restoreFPUState(_: *const FPUState) void {}
    pub fn setTaskSwitched() void {}
};

pub const cpuid = struct {
    pub fn init() void {
        // Could read MIDR_EL1, etc. For now, no-op.
    }
};

pub const Regs = struct {
    pub fn init() Regs {
        return Regs{};
    }
    pub fn setStackPointer(_: *Regs, _: usize) void {}
    pub fn isRing3(_: *Regs) bool {
        return false; // No ring concept on aarch64; stub always returns kernel mode
    }
};

pub const cpu = struct {
    pub fn disableInterrupts() void {
        asm volatile ("msr daifset, #0xf");
    }
    pub fn enableInterrupts() void {
        asm volatile ("msr daifclr, #0xf");
    }
    pub fn areIntEnabled() bool {
        var daif: u64 = undefined;
        asm volatile ("mrs %[daif], daif"
            : [daif] "=r" (daif),
        );
        // DAIF bits: D(9) A(8) I(7) F(6) — if I bit (7) is clear, IRQs are enabled
        return (daif & (1 << 7)) == 0;
    }
    pub fn getStackFrameAddr() usize {
        return asm volatile ("mov %[result], x29"
            : [result] "=r" (-> usize),
        );
    }
};

pub const syscalls = struct {
    pub fn initSyscalls() void {}
};

pub fn archReschedule() void {}

pub fn setupStack(_: usize, _: usize, _: usize, _: usize, _: usize) usize {
    return 0;
}

pub fn pageAlign(addr: usize, _: bool) usize {
    return addr & ~@as(usize, PAGE_SIZE - 1);
}

pub fn isPageAligned(addr: usize) bool {
    return addr & (PAGE_SIZE - 1) == 0;
}

pub const PAGE_SIZE: usize = 4096;
pub const IDT_MAX_DESCRIPTORS: usize = 256;
pub const CPU_EXCEPTION_COUNT: usize = 32;
pub const SYSCALL_INTERRUPT: usize = 0x80;

//! Shared types/helpers for the in-kernel test runner.

const std = @import("std");
const krn = @import("../main.zig");
const arch = @import("arch");

const QEMU_EXIT_PORT: u16 = 0xf4;
pub const EXIT_OK: u8 = 0x10;
pub const EXIT_FAIL: u8 = 0x11;

pub fn qemuExit(code: u8) noreturn {
    arch.io.outl(QEMU_EXIT_PORT, code);
    while (true) asm volatile ("hlt");
}

pub fn slog(msg: []const u8) void {
    krn.serial.print(msg);
}

pub fn slogf(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, fmt, args) catch return;
    krn.serial.print(out);
}

pub const TestFn = *const fn () bool;

pub const TestCase = struct {
    name: []const u8,
    run: TestFn,
};

pub const Subsystem = struct {
    name: []const u8,
    cases: []const TestCase,
};

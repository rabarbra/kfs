//! In-kernel KUnit-style test runner.
//!
//! Driven by `-Dtest=true`. Boots the kernel through fs/devices init, then
//! runs each registered subsystem's cases, prints PASS/FAIL on serial, and
//! exits QEMU through the `isa-debug-exit` device on port 0xf4.
//!
//! Add a new subsystem: drop `xxx_tests.zig` next to this file with a
//! `pub const cases` array, then list it in `subsystems` below.

const r = @import("./runner.zig");
const utils = @import("./utils_tests.zig");
const mm = @import("./mm_tests.zig");
const sched = @import("./sched_tests.zig");
const time = @import("./time_tests.zig");
const signals = @import("./signals_tests.zig");
const fs = @import("./fs_tests.zig");

const subsystems = [_]r.Subsystem{
    .{ .name = "utils",   .cases = &utils.cases },
    .{ .name = "mm",      .cases = &mm.cases },
    .{ .name = "sched",   .cases = &sched.cases },
    .{ .name = "time",    .cases = &time.cases },
    .{ .name = "signals", .cases = &signals.cases },
    .{ .name = "fs",      .cases = &fs.cases },
};

pub fn runAll() noreturn {
    r.slog("\n[KUNIT] === starting in-kernel tests ===\n");
    var total_pass: usize = 0;
    var total_fail: usize = 0;
    for (subsystems) |sub| {
        r.slogf("[KUNIT] -- {s} --\n", .{sub.name});
        var sub_pass: usize = 0;
        var sub_fail: usize = 0;
        for (sub.cases) |c| {
            const ok = c.run();
            if (ok) {
                r.slogf("[KUNIT] PASS: {s}.{s}\n", .{ sub.name, c.name });
                sub_pass += 1;
            } else {
                r.slogf("[KUNIT] FAIL: {s}.{s}\n", .{ sub.name, c.name });
                sub_fail += 1;
            }
        }
        r.slogf("[KUNIT] {s}: {d}/{d} passed\n",
            .{ sub.name, sub_pass, sub_pass + sub_fail });
        total_pass += sub_pass;
        total_fail += sub_fail;
    }
    r.slogf("[KUNIT] summary: {d} passed, {d} failed across {d} subsystems\n",
        .{ total_pass, total_fail, subsystems.len });
    if (total_fail == 0) {
        r.slog("[KUNIT] === ALL PASS ===\n");
        r.qemuExit(r.EXIT_OK);
    } else {
        r.slog("[KUNIT] === FAIL ===\n");
        r.qemuExit(r.EXIT_FAIL);
    }
}

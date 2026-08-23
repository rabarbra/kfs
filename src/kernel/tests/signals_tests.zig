//! In-kernel tests for signal helpers.
//! Full delivery is exercised in the userspace integration suite; here we
//! cover the pure helpers that are usable from kernel context.

const r = @import("./runner.zig");
const krn = @import("../main.zig");

fn case_sigmask_layout() bool {
    // Bit (n-1) for signal n.
    if (krn.signals.sigmask(.SIGHUP) != 0x1) return false;          // 1
    if (krn.signals.sigmask(.SIGINT) != 0x2) return false;          // 2
    if (krn.signals.sigmask(.SIGKILL) != (1 << 8)) return false;    // 9
    if (krn.signals.sigmask(.SIGUSR1) != (1 << 9)) return false;    // 10
    return true;
}

fn case_sigmask_distinct() bool {
    const a = krn.signals.sigmask(.SIGHUP);
    const b = krn.signals.sigmask(.SIGINT);
    return a != b and (a & b) == 0;
}

pub const cases = [_]r.TestCase{
    .{ .name = "sigmask_layout",   .run = case_sigmask_layout },
    .{ .name = "sigmask_distinct", .run = case_sigmask_distinct },
};

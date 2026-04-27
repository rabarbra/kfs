//! In-kernel tests for time helpers (jiffies + timespec arithmetic).

const r = @import("./runner.zig");
const krn = @import("../main.zig");

fn case_currentMs_monotonic() bool {
    const t0 = krn.currentMs();
    // Just yield a handful of times. Zombie kthreads from sched tests are
    // still in the runqueue, so each reschedule() walks past them.
    var i: usize = 0;
    while (i < 1000) : (i += 1) krn.sched.reschedule();
    const t1 = krn.currentMs();
    return t1 >= t0;
}

fn case_timespec_isValid() bool {
    var ts: krn.kernel_timespec = .{ .tv_sec = 0, .tv_nsec = 0 };
    if (!ts.isValid()) return false;
    ts = .{ .tv_sec = -1, .tv_nsec = 0 };
    if (ts.isValid()) return false;
    ts = .{ .tv_sec = 0, .tv_nsec = 1_000_000_000 };
    if (ts.isValid()) return false;
    return true;
}

fn case_timespec_fromMSec() bool {
    const ts = krn.kernel_timespec.fromMSec(2500);
    return ts.tv_sec == 2 and ts.tv_nsec == 500_000_000;
}

fn case_timespec_fromMSec_zero() bool {
    const ts = krn.kernel_timespec.fromMSec(0);
    return ts.tv_sec == 0 and ts.tv_nsec == 0;
}

fn case_timespec_now_omit() bool {
    const now: krn.kernel_timespec = .{
        .tv_sec = 0,
        .tv_nsec = krn.time.UTIME_NOW,
    };
    if (!now.isNow()) return false;
    if (now.isOmit()) return false;
    if (!now.isValid()) return false;
    const omit: krn.kernel_timespec = .{
        .tv_sec = 0,
        .tv_nsec = krn.time.UTIME_OMIT,
    };
    if (omit.isNow()) return false;
    if (!omit.isOmit()) return false;
    if (!omit.isValid()) return false;
    return true;
}

pub const cases = [_]r.TestCase{
    .{ .name = "currentMs_monotonic",    .run = case_currentMs_monotonic },
    .{ .name = "timespec_isValid",       .run = case_timespec_isValid },
    .{ .name = "timespec_fromMSec",      .run = case_timespec_fromMSec },
    .{ .name = "timespec_fromMSec_zero", .run = case_timespec_fromMSec_zero },
    .{ .name = "timespec_now_omit",      .run = case_timespec_now_omit },
};

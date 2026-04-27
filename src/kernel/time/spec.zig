const krn = @import("../main.zig");

pub const UTIME_NOW = 0x3fffffff;
pub const UTIME_OMIT = 0x3ffffffe;

pub const kernel_timespec = extern struct {
    tv_sec: i32,
    tv_nsec: i32,

    pub inline fn isValid(self: *const kernel_timespec) bool {
        if (self.tv_sec < 0)
            return false;
        if (self.tv_nsec == UTIME_NOW or self.tv_nsec == UTIME_OMIT)
            return true;
        return self.tv_nsec >= 0 and self.tv_nsec <= 999999999;
    }

    pub inline fn isNow(self: *const kernel_timespec) bool {
        return self.tv_nsec == UTIME_NOW;
    }

    pub inline fn isOmit(self: *const kernel_timespec) bool {
        return self.tv_nsec == UTIME_OMIT;
    }

    pub inline fn fromMSec(ms: u64) kernel_timespec {
        return kernel_timespec{
            .tv_sec =  @intCast(@divTrunc(ms, 1000)),
            .tv_nsec = @intCast(@rem(ms, 1000) * 1000_000),
        };
    }

    pub inline fn sub(
        self: *const kernel_timespec,
        other: *const kernel_timespec
    ) kernel_timespec {
        var res = self.*;
        res.tv_sec -= other.tv_sec;
        if (other.tv_nsec > res.tv_nsec) {
            res.tv_sec -= 1;
            res.tv_nsec = 1_000_000_000 - (other.tv_nsec - res.tv_nsec);
        } else {
            res.tv_nsec -= other.tv_nsec;
        }
        return res;
    }
};

pub const kernel_timespec64 = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

// ---- inline unit tests ----

const testing = @import("std").testing;

test "isValid rejects negative seconds and out-of-range ns" {
    var ts: kernel_timespec = .{ .tv_sec = -1, .tv_nsec = 0 };
    try testing.expect(!ts.isValid());
    ts = .{ .tv_sec = 0, .tv_nsec = 1_000_000_000 };
    try testing.expect(!ts.isValid());
    ts = .{ .tv_sec = 0, .tv_nsec = -1 };
    try testing.expect(!ts.isValid());
}

test "isValid accepts UTIME_NOW and UTIME_OMIT regardless of ns range" {
    const now: kernel_timespec = .{ .tv_sec = 0, .tv_nsec = UTIME_NOW };
    try testing.expect(now.isValid());
    try testing.expect(now.isNow());
    const omit: kernel_timespec = .{ .tv_sec = 0, .tv_nsec = UTIME_OMIT };
    try testing.expect(omit.isValid());
    try testing.expect(omit.isOmit());
}

test "fromMSec splits ms cleanly into seconds + nanos" {
    const ts = kernel_timespec.fromMSec(1500);
    try testing.expectEqual(@as(i32, 1), ts.tv_sec);
    try testing.expectEqual(@as(i32, 500_000_000), ts.tv_nsec);
}

test "fromMSec at zero" {
    const ts = kernel_timespec.fromMSec(0);
    try testing.expectEqual(@as(i32, 0), ts.tv_sec);
    try testing.expectEqual(@as(i32, 0), ts.tv_nsec);
}

test "fromMSec at exact second boundary has no nanos" {
    const ts = kernel_timespec.fromMSec(3000);
    try testing.expectEqual(@as(i32, 3), ts.tv_sec);
    try testing.expectEqual(@as(i32, 0), ts.tv_nsec);
}

test "sub yields delta when nsec doesn't underflow" {
    const a: kernel_timespec = .{ .tv_sec = 5, .tv_nsec = 800_000_000 };
    const b: kernel_timespec = .{ .tv_sec = 2, .tv_nsec = 100_000_000 };
    const d = a.sub(&b);
    try testing.expectEqual(@as(i32, 3), d.tv_sec);
    try testing.expectEqual(@as(i32, 700_000_000), d.tv_nsec);
}

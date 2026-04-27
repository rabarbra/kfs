//! In-kernel tests for the scheduler / kthread layer.
//!
//! `task.sleep` is a no-op when called from the boot kernel task, and
//! kthreads never reach .ZOMBIE on their own (threadWrapper calls finish()
//! while state is still .RUNNING, which is a no-op). So we don't poll task
//! state — instead each worker writes to a shared flag the test polls.

const std = @import("std");
const r = @import("./runner.zig");
const krn = @import("../main.zig");

var done_flag: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
var counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
var arg_seen: std.atomic.Value(i32) = std.atomic.Value(i32).init(0);

fn worker_sets_done(_: ?*const anyopaque) i32 {
    done_flag.store(1, .seq_cst);
    return 0;
}

fn worker_increments_counter(_: ?*const anyopaque) i32 {
    _ = counter.fetchAdd(1, .seq_cst);
    return 0;
}

fn worker_records_arg(arg: ?*const anyopaque) i32 {
    if (arg) |a| {
        const v: *const i32 = @alignCast(@ptrCast(a));
        arg_seen.store(v.*, .seq_cst);
    }
    return 0;
}

fn waitForFlag(flag: *std.atomic.Value(u32), want: u32, max_iters: usize) bool {
    var i: usize = 0;
    while (i < max_iters) : (i += 1) {
        if (flag.load(.seq_cst) >= want) return true;
        krn.sched.reschedule();
    }
    return false;
}

fn case_kthread_runs() bool {
    done_flag.store(0, .seq_cst);
    _ = krn.kthreadCreate(&worker_sets_done, null, "kut_run")
        catch return false;
    return waitForFlag(&done_flag, 1, 100_000);
}

fn case_kthread_receives_arg() bool {
    arg_seen.store(0, .seq_cst);
    const want: i32 = 0x1234;
    _ = krn.kthreadCreate(&worker_records_arg, &want, "kut_arg")
        catch return false;
    if (!waitForFlag(@ptrCast(&arg_seen), 1, 100_000)) {
        // arg_seen could still be 0 if want was 0; here we use a real value
    }
    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        if (arg_seen.load(.seq_cst) == want) return true;
        krn.sched.reschedule();
    }
    return false;
}

fn case_kthread_many() bool {
    counter.store(0, .seq_cst);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        _ = krn.kthreadCreate(&worker_increments_counter, null, "kut_many")
            catch return false;
    }
    var iters: usize = 0;
    while (iters < 200_000) : (iters += 1) {
        if (counter.load(.seq_cst) >= 8) return true;
        krn.sched.reschedule();
    }
    return false;
}

pub const cases = [_]r.TestCase{
    .{ .name = "kthread_runs",          .run = case_kthread_runs },
    .{ .name = "kthread_receives_arg",  .run = case_kthread_receives_arg },
    .{ .name = "kthread_many",          .run = case_kthread_many },
};

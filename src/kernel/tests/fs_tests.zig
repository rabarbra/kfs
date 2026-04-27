//! In-kernel tests for the VFS layer (path helpers + a basic round-trip).
//!
//! At test-runner time, fs.init() has run and the in-memory filesystems
//! (devfs, sysfs, procfs) are mounted, but no block-backed root is mounted
//! yet — the on-disk rootfs is plugged in later by move_root(). So any
//! test here must work entirely against the boot-time mounts.

const r = @import("./runner.zig");
const krn = @import("../main.zig");

fn case_path_isRelative() bool {
    if (krn.fs.path.isRelative("foo/bar") != true) return false;
    if (krn.fs.path.isRelative("./foo") != true) return false;
    if (krn.fs.path.isRelative("/abs/path") != false) return false;
    if (krn.fs.path.isRelative("") != false) return false;
    return true;
}

fn case_path_remove_trailing_slashes() bool {
    const a = krn.fs.path.remove_trailing_slashes("/foo/bar//");
    if (a.len != 8) return false; // "/foo/bar"
    if (a[a.len - 1] != 'r') return false;

    const b = krn.fs.path.remove_trailing_slashes("/");
    if (b.len != 1 or b[0] != '/') return false;

    const c = krn.fs.path.remove_trailing_slashes("/no/trailing");
    if (c.len != 12) return false;
    return true;
}

fn case_resolve_root() bool {
    const p = krn.fs.path.resolve("/") catch return false;
    defer p.release();
    return p.isRoot();
}

fn case_resolve_dev() bool {
    // devfs is mounted on /dev at this point (before move_root()).
    const p = krn.fs.path.resolve("/dev") catch return false;
    defer p.release();
    return true;
}

pub const cases = [_]r.TestCase{
    .{ .name = "path_isRelative",            .run = case_path_isRelative },
    .{ .name = "path_remove_trailing_slash", .run = case_path_remove_trailing_slashes },
    .{ .name = "resolve_root",               .run = case_resolve_root },
    .{ .name = "resolve_dev",                .run = case_resolve_dev },
};

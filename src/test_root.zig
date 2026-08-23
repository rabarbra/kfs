//! Discovery root for host-side unit tests.
//!
//! Lists every source file with inline `test "..."` blocks runnable on the
//! host (no `arch`/freestanding deps). To add tests for a new pure file,
//! drop `test "..." {}` blocks at the bottom of that file, then add one line
//! below pointing at it. `build.zig` does not change.
//!
//! Anywhere under `src/` works — relative paths from this file's directory.

comptime {
    _ = @import("./kernel/utils/list.zig");
    _ = @import("./kernel/utils/tree.zig");
    _ = @import("./kernel/time/spec.zig");
    // Add new pure-logic source files here, anywhere under src/:
    //   _ = @import("./kernel/fs/some_pure_helper.zig");
    //   _ = @import("./debug/some_pure_helper.zig");
}

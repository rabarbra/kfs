//! In-kernel tests for memory management (kmalloc/kfree, vmalloc).

const r = @import("./runner.zig");
const krn = @import("../main.zig");

fn case_kmalloc_roundtrip() bool {  
    const slice = krn.mm.kmallocSlice(u8, 256) orelse return false;
    defer krn.mm.kfree(slice.ptr);
    if (slice.len < 256) return false;
    var i: usize = 0;
    while (i < 256) : (i += 1) slice[i] = @truncate(i);
    i = 0;
    while (i < 256) : (i += 1) {
        if (slice[i] != @as(u8, @truncate(i))) return false;
    }
    return true;
}

fn case_kmalloc_independence() bool {
    const a = krn.mm.kmallocSlice(u8, 64) orelse return false;
    const b = krn.mm.kmallocSlice(u8, 64) orelse {
        krn.mm.kfree(a.ptr);
        return false;
    };
    defer krn.mm.kfree(a.ptr);
    defer krn.mm.kfree(b.ptr);
    if (a.ptr == b.ptr) return false;
    @memset(a, 0xAA);
    @memset(b, 0x55);
    for (a) |v| if (v != 0xAA) return false;
    for (b) |v| if (v != 0x55) return false;
    return true;
}

fn case_kmalloc_many_small() bool {
    const N = 64;
    var ptrs: [N]?[]u8 = .{null} ** N;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const s = krn.mm.kmallocSlice(u8, 32) orelse {
            // unwind on failure
            for (ptrs[0..i]) |p| if (p) |q| krn.mm.kfree(q.ptr);
            return false;
        };
        @memset(s, @truncate(i));
        ptrs[i] = s;
    }
    // verify each block kept its own contents
    i = 0;
    while (i < N) : (i += 1) {
        const s = ptrs[i].?;
        for (s) |v| if (v != @as(u8, @truncate(i))) {
            for (ptrs) |p| if (p) |q| krn.mm.kfree(q.ptr);
            return false;
        };
    }
    for (ptrs) |p| if (p) |q| krn.mm.kfree(q.ptr);
    return true;
}

fn case_ksize_at_least_request() bool {
    const slice = krn.mm.kmallocSlice(u8, 100) orelse return false;
    defer krn.mm.kfree(slice.ptr);
    const k = krn.mm.ksize(@ptrCast(slice.ptr));
    return k >= 100;
}

fn case_kmalloc_alloc_free_alloc_reuses() bool {
    // Not strictly required by the API, but on most allocators an immediate
    // free of a freshly-allocated block makes the same address available
    // again. This catches gross leaks/corruption of the free list.
    const a = krn.mm.kmallocSlice(u8, 64) orelse return false;
    const addr1 = @intFromPtr(a.ptr);
    krn.mm.kfree(a.ptr);
    const b = krn.mm.kmallocSlice(u8, 64) orelse return false;
    const addr2 = @intFromPtr(b.ptr);
    krn.mm.kfree(b.ptr);
    return addr1 == addr2;
}

fn case_vmalloc_roundtrip() bool {
    const slice = krn.mm.vmallocSlice(u8, 4096) orelse return false;
    defer krn.mm.vfreeSlice(slice);
    @memset(slice, 0xCD);
    for (slice) |v| if (v != 0xCD) return false;
    return true;
}

pub const cases = [_]r.TestCase{
    .{ .name = "kmalloc_roundtrip",         .run = case_kmalloc_roundtrip },
    .{ .name = "kmalloc_independence",      .run = case_kmalloc_independence },
    .{ .name = "kmalloc_many_small",        .run = case_kmalloc_many_small },
    .{ .name = "ksize_at_least_request",    .run = case_ksize_at_least_request },
    .{ .name = "kmalloc_alloc_free_reuses", .run = case_kmalloc_alloc_free_alloc_reuses },
    .{ .name = "vmalloc_roundtrip",         .run = case_vmalloc_roundtrip },
};

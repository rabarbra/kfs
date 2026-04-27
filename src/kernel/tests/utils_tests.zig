//! In-kernel tests for utils (list, tree, ringbuf, waitqueue).

const r = @import("./runner.zig");
const krn = @import("../main.zig");

fn case_list_basic() bool {
    var h = krn.list.ListHead.init();
    h.setup();
    if (!h.isEmpty()) return false;
    var n = krn.list.ListHead.init();
    n.setup();
    h.add(&n);
    if (h.isEmpty()) return false;
    n.del();
    if (!h.isEmpty()) return false;
    return true;
}

fn case_list_iterator_count() bool {
    var h = krn.list.ListHead.init();
    h.setup();
    var nodes: [4]krn.list.ListHead = undefined;
    for (&nodes) |*n| {
        n.* = krn.list.ListHead.init();
        n.setup();
        h.add(n);
    }
    var it = h.iterator();
    var seen: usize = 0;
    while (it.next()) |_| : (seen += 1) {
        if (seen > 10) return false;
    }
    // head + 4 nodes
    return seen == 5;
}

fn case_tree_basic() bool {
    var n = krn.tree.TreeNode.init();
    n.setup();
    if (n.hasChildren()) return false;
    if (n.hasSiblings()) return false;
    var s = krn.tree.TreeNode.init();
    s.setup();
    n.addSibling(&s);
    if (!n.hasSiblings()) return false;
    return true;
}

fn case_ringbuf_push_pop() bool {
    var rb = krn.ringbuf.RingBuf.new(16) catch return false;
    defer rb.deinit();
    if (!rb.isEmpty()) return false;
    if (!rb.push('a')) return false;
    if (!rb.push('b')) return false;
    if (!rb.push('\n')) return false;
    if (!rb.hasLine()) return false;
    if (rb.len() != 3) return false;
    if ((rb.pop() orelse 0) != 'a') return false;
    if ((rb.pop() orelse 0) != 'b') return false;
    if ((rb.pop() orelse 0) != '\n') return false;
    return rb.isEmpty();
}

fn case_ringbuf_full_rejects() bool {
    // Power-of-two; one slot is unusable per ring-buffer convention.
    var rb = krn.ringbuf.RingBuf.new(8) catch return false;
    defer rb.deinit();
    var written: usize = 0;
    while (rb.push('x')) written += 1;
    if (!rb.isFull()) return false;
    if (written != rb.capacity() - 1) return false;
    return true;
}

fn case_ringbuf_line_counting() bool {
    var rb = krn.ringbuf.RingBuf.new(32) catch return false;
    defer rb.deinit();
    _ = rb.pushSlice("ab\ncd\nef");
    if (!rb.hasLine()) return false;
    var buf: [16]u8 = undefined;
    const n = rb.readLineInto(buf[0..]);
    if (n != 3) return false; // "ab\n"
    if (buf[0] != 'a' or buf[1] != 'b' or buf[2] != '\n') return false;
    if (!rb.hasLine()) return false;
    const m = rb.readLineInto(buf[0..]);
    if (m != 3) return false; // "cd\n"
    if (rb.hasLine()) return false; // "ef" has no newline yet
    return true;
}

pub const cases = [_]r.TestCase{
    .{ .name = "list_basic",            .run = case_list_basic },
    .{ .name = "list_iterator_count",   .run = case_list_iterator_count },
    .{ .name = "tree_basic",            .run = case_tree_basic },
    .{ .name = "ringbuf_push_pop",      .run = case_ringbuf_push_pop },
    .{ .name = "ringbuf_full_rejects",  .run = case_ringbuf_full_rejects },
    .{ .name = "ringbuf_line_counting", .run = case_ringbuf_line_counting },
};

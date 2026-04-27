
pub const TreeNode = struct {
    parent: ?*TreeNode  = null,
    child: ?*TreeNode   = null,
    next: ?*TreeNode    = null,
    prev: ?*TreeNode    = null,

    pub fn init() TreeNode {
        return .{};
    }

    pub fn setup(self: *TreeNode) void {
        self.parent = null;
        self.child = null;
        self.next = self;
        self.prev = self;
    }

    pub fn hasChildren(self: *TreeNode) bool {
        return self.child != null;
    }

    pub fn childrenCount(self: *TreeNode) u32 {
        var count: u32 = 0;
        if (self.child) |ch| {
            var it = ch.siblingsIterator();
            while (it.next()) |_| {
                count += 1;
            }
        }
        return count;
    }

    pub fn hasSiblings(self: *TreeNode) bool {
        return self.next != self;
    }

    pub fn addSibling(self: *TreeNode, new: *TreeNode) void {
        new.next = self;
        new.prev = self.prev;

        self.prev.?.next = new;
        self.prev = new;
        new.parent = self.parent;
    }

    pub fn addChild(self: *TreeNode, new: *TreeNode) void {
        if (self.hasChildren()) {
            self.child.?.addSibling(new);
        } else {
            self.child = new;
        }
        new.parent = self;
    }

    pub fn setParent(self: *TreeNode, parent: *TreeNode) void {
        var it = self.siblingsIterator();
        while (it.next()) |i| {
            i.curr.parent = parent;
        }
    }

    pub fn addChildren(self: *TreeNode, new: *TreeNode) void {
        new.setParent(self);
        if (self.hasChildren()) {
            const old_prev_child = self.child.?.prev;
            const new_prev_child = new.prev;
            new_prev_child.?.next = self.child;
            self.child.?.prev = new_prev_child;
            new.prev = old_prev_child;
            old_prev_child.?.next = new;
        } else {
            self.child = new;
        }
    }

    pub fn del(self: *TreeNode) void {
        if (self.hasSiblings()) {
            if (self.parent.?.child == self) {
                self.parent.?.child = self.next;
            }
            self.prev.?.next = self.next;
            self.next.?.prev = self.prev;
        } else if (self.parent) |prnt| {
            prnt.child = null;
        }
        if (self.hasChildren()) {
            if (self.parent) |prnt| {
                prnt.addChildren(self.child.?);
            }
        }
        self.setup();
    }

    pub fn siblingsIterator(self: *TreeNode) Iterator {
        return Iterator.init(self);
    }

    pub fn entry(self: *TreeNode, comptime T: type, comptime member: []const u8) *T {
        return @alignCast(@fieldParentPtr(member, self));
    }
};

pub const Iterator = struct {
    curr: *TreeNode,
    head: ?*TreeNode,
    used: bool = false,

    pub fn init(head: *TreeNode) Iterator {
        return .{
            .curr = head,
            .head = head,
        };
    }

    pub fn next(self: *Iterator) ?*Iterator {
        if (self.head) |head| {
            if (self.curr == head and !self.used) {
                self.used = true;
                return self;
            }
            if (self.curr.next == null)
                return null;
            self.curr = self.curr.next.?;
            if (self.curr == head)
                return null;
            return self;
        }
        return null;
    }

    pub fn isLast(self: *Iterator) bool {
        return self.head == null or self.curr.next == self.head.?;
    }

    pub fn reset(self: *Iterator, removed: *TreeNode) void {
        if (self.head == null)
            return;
        if (self.head.? == removed) {
            if (self.head.?.hasSiblings()) {
                const new_head = self.head.?.next.?;
                self.head = new_head;
                self.curr = new_head;
                self.used = false;
            } else {
                self.head = null;
            }
        }
    }
};

// ---- inline unit tests ----

const testing = @import("std").testing;

test "setup yields no children, no siblings" {
    var n = TreeNode.init();
    n.setup();
    try testing.expect(!n.hasChildren());
    try testing.expect(!n.hasSiblings());
    try testing.expectEqual(@as(u32, 0), n.childrenCount());
}

test "addSibling creates ring of two" {
    var a = TreeNode.init();
    a.setup();
    var b = TreeNode.init();
    b.setup();
    a.addSibling(&b);
    try testing.expect(a.hasSiblings());
    try testing.expect(b.hasSiblings());
    try testing.expectEqual(&b, a.next.?);
    try testing.expectEqual(&a, b.next.?);
}

test "addChild attaches child and sets its parent" {
    var p = TreeNode.init();
    p.setup();
    var c = TreeNode.init();
    c.setup();
    p.addChild(&c);
    try testing.expect(p.hasChildren());
    try testing.expectEqual(&p, c.parent.?);
    try testing.expectEqual(&c, p.child.?);
    try testing.expectEqual(@as(u32, 1), p.childrenCount());
}

test "addChild on existing parent appends as sibling" {
    var p = TreeNode.init();
    p.setup();
    var c1 = TreeNode.init();
    c1.setup();
    var c2 = TreeNode.init();
    c2.setup();
    p.addChild(&c1);
    p.addChild(&c2);
    try testing.expectEqual(@as(u32, 2), p.childrenCount());
    try testing.expectEqual(&p, c1.parent.?);
    try testing.expectEqual(&p, c2.parent.?);
}

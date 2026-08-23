
pub const Iterator = struct {
    curr: *ListHead,
    head: *ListHead,
    used: bool = false,

    pub fn init(head: *ListHead) Iterator {
        return .{
            .curr = head,
            .head = head,
        };
    }

    pub fn next(self: *Iterator) ?*Iterator {
        if (self.curr == self.head and !self.used) {
            self.used = true;
            return self;
        }
        if (self.curr.next == null)
            return null;
        self.curr = self.curr.next.?;
        if (self.curr == self.head)
            return null;
        return self;
    }

    pub fn isLast(self: *Iterator) bool {
        return self.curr.next == self.head;
    }

    pub fn toEnd(self: *Iterator) void {
        self.used = true;
        self.curr = self.head.prev.?;
    }
};

pub const ListHead = extern struct {
    next: ?*ListHead,
    prev: ?*ListHead,

    pub fn init() ListHead {
        return .{
            .next = null,
            .prev = null,
        };
    }

    pub fn setup(self: *ListHead) void {
        self.next = self;
        self.prev = self;
    }

    pub fn iterator(self: *ListHead) Iterator {
        return Iterator.init(self);
    }

    pub fn entry(self: *ListHead, comptime T: type, comptime member: []const u8) *T {
        return @fieldParentPtr(member, self);
    }

    pub fn add(self: *ListHead, new: *ListHead) void {
        const next = self.next;
        self.next = new;
        new.prev = self;
        new.next = next;
        if (next) |nxt| {
            nxt.prev = new;
        }
    }

    pub fn addTail(self: *ListHead, new: *ListHead) void {
        if (self.prev == null) {
            new.next = self;
            self.prev = new;
            new.prev = null;
        } else {
            self.prev.?.add(new);
        }
    }

    pub fn del(self: *ListHead) void {
        if (self.prev == null and self.next == null)
            return;

        if (self.prev) |prev| {
            prev.next = self.next;
        }
        if (self.next) |next| {
            next.prev = self.prev;
        }

        self.prev = null;
        self.next = null;
    }

    pub fn isEmpty(self: *ListHead) bool {
        return self.next == self;
    }
};

pub fn containerOf(comptime T: type, ptr: usize, comptime member: []const u8) *T {
    const offset = @offsetOf(T, member);
    const result: *T = @ptrFromInt(ptr - offset);
    return result;
}

pub fn listMap(
    comptime T: type,
    head: *ListHead, f: fn (arg: *T) void,
    comptime member: [] const u8
) void {
    var buf: ?*ListHead = head;
    while (buf != null) : (buf = buf.?.next) {
        f(containerOf(T, @intFromPtr(buf.?), member));
    }
}

// ---- inline unit tests (run via `zig build test`) ----

const testing = @import("std").testing;

test "ListHead setup makes self-referential, isEmpty true" {
    var h = ListHead.init();
    h.setup();
    try testing.expect(h.isEmpty());
    try testing.expectEqual(&h, h.next.?);
    try testing.expectEqual(&h, h.prev.?);
}

test "add inserts after head; isEmpty becomes false" {
    var h = ListHead.init();
    h.setup();
    var n = ListHead.init();
    n.setup();
    h.add(&n);
    try testing.expect(!h.isEmpty());
    try testing.expectEqual(&n, h.next.?);
    try testing.expectEqual(&h, n.prev.?);
}

test "del unlinks and clears pointers" {
    var h = ListHead.init();
    h.setup();
    var n = ListHead.init();
    n.setup();
    h.add(&n);
    n.del();
    try testing.expect(h.isEmpty());
    try testing.expect(n.prev == null);
    try testing.expect(n.next == null);
}

test "iterator visits inserted nodes once" {
    var h = ListHead.init();
    h.setup();
    var a = ListHead.init();
    a.setup();
    var b = ListHead.init();
    b.setup();
    var c = ListHead.init();
    c.setup();
    h.add(&a);
    h.add(&b);
    h.add(&c);
    var it = h.iterator();
    var seen: usize = 0;
    while (it.next()) |_| : (seen += 1) {
        if (seen > 8) break;
    }
    try testing.expectEqual(@as(usize, 4), seen);
}

test "containerOf recovers parent struct pointer" {
    const S = struct { a: u32, link: ListHead, b: u32 };
    var s = S{ .a = 1, .link = ListHead.init(), .b = 2 };
    const recovered = containerOf(S, @intFromPtr(&s.link), "link");
    try testing.expectEqual(&s, recovered);
    try testing.expectEqual(@as(u32, 1), recovered.a);
    try testing.expectEqual(@as(u32, 2), recovered.b);
}

test "addTail puts node at the end" {
    var h = ListHead.init();
    h.setup();
    var a = ListHead.init();
    a.setup();
    var b = ListHead.init();
    b.setup();
    h.addTail(&a);
    h.addTail(&b);
    // After two tail-adds: head -> a -> b -> head
    try testing.expectEqual(&a, h.next.?);
    try testing.expectEqual(&b, h.prev.?);
}

test "iterator on empty list visits only the head sentinel" {
    var h = ListHead.init();
    h.setup();
    var it = h.iterator();
    var seen: usize = 0;
    while (it.next()) |_| : (seen += 1) {
        if (seen > 4) break;
    }
    try testing.expectEqual(@as(usize, 1), seen);
}

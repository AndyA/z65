const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const cache_line = std.atomic.cache_line;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;

fn PadInt(comptime T: type, comptime size: usize) type {
    return @Int(.unsigned, (size - @sizeOf(T)) * 8);
}

pub const QueuedSpinlock = struct {
    const Self = @This();

    const QRef = ?*QueueNode;

    pub const QueueNode = struct {
        _: void align(cache_line) = {},
        next: QRef = null,
        locked: bool = true,
        pad: PadInt(struct { QRef, bool }, cache_line) = undefined,
    };

    comptime {
        assert(@alignOf(QueueNode) == cache_line);
        assert(@sizeOf(QueueNode) == cache_line);
    }

    comptime {
        assert(@alignOf(Self) == cache_line);
        assert(@sizeOf(Self) == cache_line);
    }

    _: void align(cache_line) = {},
    tail: QRef = null,
    // pad: PadInt(struct { QRef }, cache_line) = undefined,

    pub fn acquire(self: *Self, node: *QueueNode) void {
        assert(node.next == null);
        assert(node.locked);

        const previous_tail = @atomicRmw(QRef, &self.tail, .Xchg, node, .monotonic);

        if (previous_tail) |tail| {
            @atomicStore(QRef, &tail.next, node, .monotonic);
            // Spin until node is unlocked
            spin: while (true) {
                std.atomic.spinLoopHint();
                const locked = @atomicRmw(bool, &node.locked, .Xchg, true, .monotonic);
                if (!locked) break :spin;
            }
        }
    }

    pub fn release(self: *Self, node: *QueueNode) void {
        assert(node.locked);
        const current_tail = @cmpxchgStrong(QRef, &self.tail, node, null, .monotonic, .monotonic);
        if (current_tail != null) {
            // This node is no longer the tail which means that we should wake up the next
            // node in the queue - but we have to wait for the node's `next` to be populated.
            // We might need to wait because the store to `next` happens after the store
            // to `tail` in `acquire`. We shouldn't have long to wait.
            spin: while (true) {
                std.atomic.spinLoopHint();
                const next = @atomicRmw(QRef, &node.next, .Xchg, null, .monotonic);
                if (next) |nn| {
                    @atomicStore(bool, &nn.locked, false, .monotonic);
                    break :spin;
                }
            }
        }

        assert(node.next == null);
        assert(node.locked);
    }
};

const TestSize = 256;
const TestThreads = 8;

const TestMsg = packed struct {
    sequence: u32,
    thread: u32,
};

fn waste_time() void {
    var total: usize = 0;
    for (0..1000) |i| {
        if (i % 51 == 0) total += 3;
        if (i % 17 == 0) total += 11;
    }
    if (total == 666) waste_time();
}

const TestArray = struct {
    msgs: [TestSize]TestMsg = undefined,
    pos: usize = 0,
    lock: QueuedSpinlock = .{},

    pub fn push(self: *TestArray, msg: TestMsg) void {
        var node: QueuedSpinlock.QueueNode = .{};
        self.lock.acquire(&node);
        defer self.lock.release(&node);

        defer self.pos += 1;
        self.msgs[self.pos] = msg;
        waste_time();
    }

    pub fn getMessages(self: *const TestArray) []const TestMsg {
        return self.msgs[0..self.pos];
    }
};

fn worker(ta: *TestArray, id: u32, count: u32) void {
    for (0..count) |i| {
        ta.push(.{ .sequence = @intCast(i), .thread = id });
    }
}

test QueuedSpinlock {
    var ta: TestArray = .{};

    var threads: [TestThreads]std.Thread = undefined;
    for (0..TestThreads) |id| {
        threads[id] = try std.Thread.spawn(
            .{},
            worker,
            .{ &ta, @as(u32, @intCast(id)), TestSize / TestThreads },
        );
    }

    for (threads) |t| {
        t.join();
    }

    var ref: TestArray = .{};
    for (0..TestThreads) |id| {
        for (0..TestSize / TestThreads) |seq| {
            ref.push(.{
                .sequence = @intCast(seq),
                .thread = @intCast(id),
            });
        }
    }

    try expectEqual(ref.pos, ta.pos);

    var got = ta;
    const Context = struct {
        pub fn lt(_: @This(), lhs: TestMsg, rhs: TestMsg) bool {
            if (lhs.thread < rhs.thread)
                return true;
            return lhs.thread == rhs.thread and lhs.sequence < rhs.sequence;
        }
    };
    std.mem.sort(TestMsg, &got.msgs, Context{}, Context.lt);
    try expectEqualDeep(ref, got);

    const reordered = for (ta.msgs[0 .. ta.pos - 1], ta.msgs[1..ta.pos]) |lhs, rhs| {
        if (!Context.lt(.{}, lhs, rhs)) break true;
    } else false;

    try expect(reordered);
}

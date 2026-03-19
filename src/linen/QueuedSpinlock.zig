const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const cache_line = std.atomic.cache_line;
const expectEqual = std.testing.expectEqual;

const Self = @This();
const QueuedSpinlock = Self;

const QRef = ?*QueueNode;

pub const QueueNode = extern struct {
    next: QRef align(cache_line) = null,
    locked: bool = true,
};

tail: QRef align(cache_line) = null,

pub fn acquire(self: *Self, node: *QueueNode) void {
    assert(node.next == null);
    assert(node.locked);
    const previous_tail = @atomicRmw(QRef, &self.tail, .Xchg, node, .monotonic);

    if (previous_tail) |tail| {
        @atomicStore(QRef, &tail.next, node, .monotonic);
        // Spin until node is unlocked
        spin: while (true) {
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
            const next = @atomicRmw(QRef, &node.next, .Xchg, null, .monotonic);
            if (next) |nn| {
                @atomicStore(bool, &nn.locked, false, .monotonic);
                break :spin;
            }
        }
    }
}

const TestSize = 256;
const TestThreads = 8;

const TestMsg = struct {
    sequence: u32,
    thread: u32,
};

fn waste_time() void {
    var total: usize = 0;
    for (0..1000) |i| {
        if (i % 51 == 0) total += 3;
        if (i % 17 == 0) total += 11;
    }
    assert(total != 666);
}

const TestArray = struct {
    msgs: [TestSize]TestMsg = undefined,
    pos: usize = 0,
    lock: QueuedSpinlock = .{},

    pub fn push(self: *TestArray, msg: TestMsg) void {
        var node: QueueNode = .{};
        self.lock.acquire(&node);
        defer self.lock.release(&node);

        defer self.pos += 1;
        self.msgs[self.pos] = msg;
        waste_time();
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

    try expectEqual(TestSize, ta.pos);

    // for (ta.msgs) |msg| {
    //     print("{any}\n", .{msg});
    // }

    // var node: QueueNode = .{};

    // try expectEqual(cache_line, @alignOf(QueueNode));
    // try expectEqual(cache_line, @alignOf(QueuedSpinlock));

    // lock.acquire(&node);
    // lock.release(&node);
    // try expectEqual(null, lock.tail);
}

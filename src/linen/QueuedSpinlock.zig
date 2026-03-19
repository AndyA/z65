const std = @import("std");
const assert = std.debug.assert;
const cache_line = std.atomic.cache_line;

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
        // Spin on node's locked
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

test QueuedSpinlock {
    var lock: QueuedSpinlock = .{};
    var node: QueueNode = .{};

    try std.testing.expectEqual(cache_line, @alignOf(QueueNode));
    try std.testing.expectEqual(cache_line, @alignOf(QueuedSpinlock));

    lock.acquire(&node);
    lock.release(&node);
    try std.testing.expectEqual(null, lock.tail);
}

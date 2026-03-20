const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const cache_line = std.atomic.cache_line;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;

pub const QueuedSpinlock = struct {
    const QueueSlot = struct {
        _: void align(cache_line) = {},
        next: ?*QueueSlot = null,
        locked: bool = true,
        lock: *QueuedSpinlock,

        pub fn acquire(self: *QueueSlot) void {
            const previous_tail = @atomicRmw(?*QueueSlot, &self.lock.tail, .Xchg, self, .monotonic);
            if (previous_tail) |tail| {
                @atomicStore(?*QueueSlot, &tail.next, self, .monotonic);
                // Spin until slot is unlocked
                spin: while (true) {
                    const locked = @atomicRmw(bool, &self.locked, .Xchg, true, .monotonic);
                    if (!locked) break :spin;
                    std.atomic.spinLoopHint();
                }
            }
        }

        pub fn release(self: *QueueSlot) void {
            const current_tail = @cmpxchgStrong(
                ?*QueueSlot,
                &self.lock.tail,
                self,
                null,
                .monotonic,
                .monotonic,
            );
            if (current_tail != null) {
                // This slot is no longer the tail which means that we should wake up the next
                // slot in the queue - but we might need to wait for this slot's `next` to be
                // populated because in `acquire()` the store to `next` happens after the store
                // to `tail`. We shouldn't have long to wait.
                spin: while (true) {
                    const next = @atomicRmw(?*QueueSlot, &self.next, .Xchg, null, .monotonic);
                    if (next) |nn| {
                        @atomicStore(bool, &nn.locked, false, .monotonic);
                        break :spin;
                    }
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    comptime {
        assert(@alignOf(QueueSlot) == cache_line);
        assert(@sizeOf(QueueSlot) == cache_line);
    }

    comptime {
        assert(@alignOf(QueuedSpinlock) == cache_line);
        assert(@sizeOf(QueuedSpinlock) == cache_line);
    }

    _: void align(cache_line) = {},
    tail: ?*QueueSlot = null,

    pub fn getSlot(self: *QueuedSpinlock) QueueSlot {
        return .{ .lock = self };
    }
};

pub const NopQueuedSpinlock = struct {
    const QueueSlot = struct {
        pub fn acquire(_: *QueueSlot) void {}
        pub fn release(_: *QueueSlot) void {}
    };
    pub fn getSlot(_: @This()) QueueSlot {
        return .{};
    }
};

const TestSize = 65536;
const TestThreads = 8;

const TestMsg = packed struct {
    sequence: u32,
    thread: u32,
};

fn waste_time() void {
    for (0..1000) |i| {
        _ = std.mem.doNotOptimizeAway(i / 19);
    }
}

const TestArray = struct {
    msgs: [TestSize]TestMsg = undefined,
    pos: usize = 0,
    lock: QueuedSpinlock = .{},

    pub fn push(self: *TestArray, msg: TestMsg) void {
        var slot = self.lock.getSlot();
        slot.acquire();
        defer slot.release();

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

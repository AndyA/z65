const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Io = std.Io;

const qs = @import("linen/queued_spinlock.zig");
const QueuedSpinlock = qs.QueuedSpinlock;
const NopQueuedSpinlock = qs.NopQueuedSpinlock;

pub fn RingBuffer(comptime T: type, comptime size: usize, comptime Spinlock: type) type {
    return struct {
        const Self = @This();

        buf: [size]T = undefined,
        pos: usize = 0,
        used: usize = 0,
        lock: Spinlock = .{},

        pub fn put(self: *Self, value: T) void {
            var slot = self.lock.getSlot();
            slot.acquire();
            defer slot.release();

            assert(self.used < size);
            self.buf[self.pos] = value;
            self.pos += 1;
            if (self.pos == size) self.pos = 0;
            self.used += 1;
        }

        pub fn get(self: *Self) T {
            var slot = self.lock.getSlot();
            slot.acquire();
            defer slot.release();

            assert(self.used > 0);
            var pos = self.pos - self.used + size;
            if (pos >= size) pos -= size;
            self.used -= 1;

            return self.buf[pos];
        }

        pub fn poll(self: *Self) ?T {
            var slot = self.lock.getSlot();
            slot.acquire();
            defer slot.release();

            if (self.used == 0)
                return null;

            return self.get();
        }
    };
}

const TestCount = 100_000_000;

fn noQueue() u32 {
    var rng = std.Random.Xoroshiro128.init(0);
    const rand = rng.random();

    var sum: u32 = 0;
    for (1..TestCount) |_| {
        sum ^= rand.int(u32);
    }
    return sum;
}

fn singleWithQueue(comptime Spinlock: type) fn () u32 {
    const shim = struct {
        pub fn fun() u32 {
            var rng = std.Random.Xoroshiro128.init(0);
            const rand = rng.random();
            var queue = RingBuffer(u32, 1024, Spinlock){};
            var sum: u32 = 0;
            for (1..TestCount) |_| {
                const x = rand.int(u32);
                queue.put(x);
                const y = queue.get();
                assert(x == y);
                sum ^= y;
            }
            return sum;
        }
    };

    return shim.fun;
}

pub fn main(init: std.process.Init) !void {
    const Test = struct {
        fun: *const fn () u32,
        name: []const u8,
    };
    const tests = [_]Test{
        .{ .fun = noQueue, .name = "no queue" },
        .{ .fun = singleWithQueue(NopQueuedSpinlock), .name = "single thread, no lock" },
        .{ .fun = singleWithQueue(QueuedSpinlock), .name = "single thread, lock" },
    };
    for (tests) |t| {
        const start_ts = Io.Clock.awake.now(init.io);
        const res = t.fun();
        const elapsed = start_ts.untilNow(init.io, .awake).toNanoseconds();
        const rate: f64 = @as(f64, @floatFromInt(TestCount)) /
            @as(f64, @floatFromInt(elapsed)) *
            1_000_000_000;

        print("{s:<40} {x:0>8} {d:>20.2}/s\n", .{ t.name, res, rate });
    }
}

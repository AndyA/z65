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

            assert(self.used <= size);
            while (self.used == size) {
                slot.release();
                slot.acquire();
            }

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

            while (self.used == 0) {
                slot.release();
                slot.acquire();
            }

            assert(self.used > 0);
            var pos = self.pos + size - self.used;
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

const TestCount = 1_000_000;

fn noQueue() u32 {
    var rng = std.Random.Xoroshiro128.init(0);
    const rand = rng.random();

    var sum: u32 = 0;
    for (0..TestCount) |_| {
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
            for (0..TestCount) |_| {
                queue.put(rand.int(u32));
                sum ^= queue.get();
            }
            return sum;
        }
    };

    return shim.fun;
}

fn threadedSingleReader(comptime threads: usize) fn () u32 {
    const Queue = RingBuffer(u32, 1024, QueuedSpinlock);

    const shim = struct {
        fn writer_worker(queue: *Queue, count: usize, rand: std.Random) void {
            for (0..count) |_| {
                queue.put(rand.int(u32));
            }
        }

        fn reader_worker(queue: *Queue, result: *u32) void {
            var sum: u32 = 0;
            for (0..TestCount) |_| {
                sum ^= queue.get();
            }
            @atomicStore(u32, result, sum, .release);
        }

        pub fn fun() u32 {
            var result: u32 = undefined;
            var queue: Queue = .{};

            const each = TestCount / threads;
            const extra = TestCount - (each * threads);

            var rng = std.Random.Xoroshiro128.init(0);
            const rand = rng.random();

            var writers: [threads]std.Thread = undefined;
            for (0..threads) |i| {
                const ration = if (i >= extra) each else each + 1;
                writers[i] = std.Thread.spawn(
                    .{},
                    writer_worker,
                    .{ &queue, ration, rand },
                ) catch unreachable;
            }

            var reader: std.Thread = std.Thread.spawn(
                .{},
                reader_worker,
                .{ &queue, &result },
            ) catch unreachable;

            for (writers) |t| t.join();
            reader.join();

            return @atomicLoad(u32, &result, .acquire);
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
        .{ .fun = threadedSingleReader(4), .name = "4 writers, 1 reader" },
        .{ .fun = threadedSingleReader(8), .name = "8 writers, 1 reader" },
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

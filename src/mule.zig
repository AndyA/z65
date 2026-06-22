const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;
const linen = @import("linen/linen.zig");

const Keyboard = struct {
    const Self = @This();
    io: Io,
    reader: *Io.Reader,
    queue: Io.Queue(u8),
    shutdown: Io.Event = .unset,
    worker: std.Thread = undefined,

    const ReadResult = union(enum) {
        input: error{ EndOfStream, ReadFailed }!u8,
        timeout: error{Canceled}!void,
        shutdown: error{Canceled}!void,
    };

    pub fn init(io: Io, reader: *Io.Reader, buffer: []u8) Self {
        return Self{ .io = io, .reader = reader, .queue = .init(buffer) };
    }

    pub fn readWithTimeout(self: *Self, timeout: ?Io.Duration) !ReadResult {
        var results: [10]ReadResult = undefined;
        var select = Io.Select(ReadResult).init(self.io, &results);
        defer _ = select.cancel();

        try select.concurrent(.input, Io.Reader.takeByte, .{self.reader});
        try select.concurrent(.shutdown, Io.Event.wait, .{ &self.shutdown, self.io });

        if (timeout) |t|
            try select.concurrent(.timeout, Io.Clock.Duration.sleep, .{
                .{ .raw = t, .clock = .awake },
                self.io,
            });

        return try select.await();
    }

    fn enqueue(self: *Self, c: u8) !void {
        try self.queue.putOne(self.io, c);
    }

    fn escape(self: *Self) !void {
        print("Escape!\n", .{});
        _ = self;
        // try self.enqueue(0x1b);
    }

    fn maybeEscape(self: *Self) !void {
        const res = try self.readWithTimeout(.fromMilliseconds(10));
        switch (res) {
            .input => |i| {
                switch (try i) {
                    '[' => {
                        try self.enqueue(0x1b);
                        try self.enqueue('[');
                    },
                    else => try self.escape(),
                }
            },
            .shutdown => {},
            .timeout => try self.escape(),
        }
    }

    fn run(self: *Self) !void {
        while (!self.shutdown.isSet()) {
            const res = try self.readWithTimeout(null);
            switch (res) {
                .input => |i| {
                    switch (try i) {
                        0x1b => try self.maybeEscape(),
                        else => |c| try self.enqueue(c),
                    }
                },
                .shutdown => {},
                .timeout => unreachable,
            }
        }
    }

    pub fn stop(self: *Self) void {
        self.shutdown.set(self.io);
    }

    pub fn start(self: *Self) !void {
        const t = try std.Thread.spawn(.{}, run, .{self});
        t.detach();
    }
};

pub fn main(init: std.process.Init) !void {
    // Set up our I/O implementation.
    var threaded: Io.Threaded = .init(init.gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const stdin = Io.File.stdin();
    const term = try linen.Term.init(.{ .stdin = stdin });
    defer term.deinit();

    // const clock: Io.Clock = .awake;
    print("Hit space to quit\n", .{});

    var io_buf: [32]u8 = undefined;
    var reader = stdin.reader(init.io, &io_buf);
    var kb_buf: [256]u8 = undefined;

    var kb: Keyboard = .init(io, &reader.interface, &kb_buf);
    try kb.start();
    defer kb.stop();

    // var last_ts: i64 = 0;
    while (true) {
        const c = try kb.queue.getOne(io);
        print("\\x{x:0>2}", .{c});
        if (c == 0x20) break;
    }

    print("Bye!\n", .{});
}

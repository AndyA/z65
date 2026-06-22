const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;
const linen = @import("linen/linen.zig");

fn Signal(comptime T: type) type {
    return struct {
        const Self = @This();
        const Handler = *const fn (ctx: *T) void;
        handler: Handler,
        context: *T,

        pub fn init(handler: Handler, context: *T) Self {
            return .{ .handler = handler, .context = context };
        }

        pub fn signal(self: Self) void {
            self.handler(self.context);
        }
    };
}

const Keyboard = struct {
    const Self = @This();
    const EscapeHandler = Signal(anyopaque);

    io: Io,
    reader: *Io.Reader,
    // on_escape: Sign
    on_escape: EscapeHandler,
    queue: Io.Queue(u8),
    trap_escape: bool = true,
    shutdown: Io.Event = .unset,

    const ReadResult = union(enum) {
        input: error{ EndOfStream, ReadFailed }!u8,
        timeout: error{Canceled}!void,
        shutdown: error{Canceled}!void,
    };

    pub fn init(io: Io, reader: *Io.Reader, buffer: []u8, on_escape: EscapeHandler) Self {
        return Self{
            .io = io,
            .reader = reader,
            .queue = .init(buffer),
            .on_escape = on_escape,
        };
    }

    fn readWithTimeout(self: *Self, timeout: ?Io.Duration) !ReadResult {
        var results: [3]ReadResult = undefined;
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

    fn handleEscape(self: *Self) !void {
        if (self.trap_escape) {
            self.on_escape.signal();
        } else {
            try self.enqueue(0x1b);
        }
    }

    fn maybeEscape(self: *Self) !void {
        const res = try self.readWithTimeout(.fromMilliseconds(10));
        switch (res) {
            .input => |i| {
                const c = try i;
                switch (c) {
                    '[' => try self.enqueue(0x1b),
                    else => try self.handleEscape(),
                }
                try self.enqueue(c);
            },
            .timeout => try self.handleEscape(),
            .shutdown => {},
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
                .timeout => unreachable,
                .shutdown => {},
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

    pub fn poll(self: *Self, timeout: ?Io.Duration) !?u8 {
        const PollResult = union(enum) {
            input: error{ Canceled, Closed }!u8,
            timeout: error{Canceled}!void,
        };
        var results: [2]PollResult = undefined;
        var select = Io.Select(PollResult).init(self.io, &results);
        defer _ = select.cancel();

        try select.concurrent(.input, Io.Queue(u8).getOne, .{ &self.queue, self.io });
        if (timeout) |t|
            try select.concurrent(.timeout, Io.Clock.Duration.sleep, .{
                .{ .raw = t, .clock = .awake },
                self.io,
            });

        return switch (try select.await()) {
            .input => |c| try c,
            .timeout => null,
        };
    }
};

fn onEscape(_: *anyopaque) void {
    print("Escape\n", .{});
}

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

    var kb: Keyboard = .init(io, &reader.interface, &kb_buf, .init(onEscape, &.{}));
    try kb.start();
    defer kb.stop();

    // var last_ts: i64 = 0;
    while (true) {
        if (try kb.poll(.fromSeconds(1))) |c| {
            print("\\x{x:0>2}", .{c});
            if (c == 0x20) break;
        } else {
            print("* ", .{});
        }
    }

    print("Bye!\n", .{});
}

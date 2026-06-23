const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

pub const InputEvent = union(enum) {
    char: u8,
    meta: enum(u8) { UP, DOWN, LEFT, RIGHT },
    escape: void,
    timeout: void,
};

pub const Engine = struct {
    const Self = @This();
    const InputQueue = Io.Queue(InputEvent);

    io: Io,
    reader: *Io.Reader,
    escape_event: *Io.Event,
    queue: InputQueue,
    queue_overflow: Io.Event = .unset,
    trap_escape: bool = true, // TODO atomic
    shutdown: Io.Event = .unset,
    worker: ?std.Thread = null,

    const ReadResult = union(enum) {
        input: error{ EndOfStream, ReadFailed }!u8,
        timeout: error{Canceled}!void,
        shutdown: error{Canceled}!void,
    };

    pub fn init(io: Io, reader: *Io.Reader, buffer: []InputEvent, escape_event: *Io.Event) Self {
        return Self{
            .io = io,
            .reader = reader,
            .queue = .init(buffer),
            .escape_event = escape_event,
        };
    }

    fn fallibleRead(self: *Self, timeout: ?Io.Duration) error{
        Canceled,
        ConcurrencyUnavailable,
    }!ReadResult {
        var results: [3]ReadResult = undefined;
        var select = Io.Select(ReadResult).init(self.io, &results);
        defer _ = select.cancel();

        try select.concurrent(.input, Io.Reader.takeByte, .{self.reader});
        try select.concurrent(.shutdown, Io.Event.wait, .{ &self.shutdown, self.io });

        if (timeout) |t|
            try select.concurrent(
                .timeout,
                Io.Clock.Duration.sleep,
                .{ .{ .raw = t, .clock = .awake }, self.io },
            );

        return try select.await();
    }

    fn read(self: *Self, timeout: ?Io.Duration) ReadResult {
        return self.fallibleRead(timeout) catch unreachable;
    }

    fn fallibleEnqueue(self: *Self, ev: InputEvent) error{ Canceled, ConcurrencyUnavailable }!void {
        const Result = union(enum) {
            put: error{ Canceled, Closed }!void,
            timeout: error{Canceled}!void,
        };
        var results: [2]Result = undefined;
        var select = Io.Select(Result).init(self.io, &results);
        defer _ = select.cancel();

        try select.concurrent(.put, InputQueue.putOne, .{ &self.queue, self.io, ev });
        try select.concurrent(
            .timeout,
            Io.Clock.Duration.sleep,
            .{ .{ .raw = .fromMilliseconds(10), .clock = .awake }, self.io },
        );

        switch (try select.await()) {
            .put => {},
            .timeout => self.queue_overflow.set(self.io),
        }
    }

    fn enqueue(self: *Self, ev: InputEvent) void {
        self.fallibleEnqueue(ev) catch unreachable;
    }

    fn handleEscape(self: *Self) void {
        if (self.trap_escape)
            self.escape_event.set(self.io)
        else
            self.enqueue(.{ .char = 0x1b });
    }

    fn maybeEscape(self: *Self) void {
        switch (self.read(.fromMilliseconds(10))) {
            .input => |i| {
                const c = i catch unreachable;
                switch (c) {
                    '[', 'O' => self.enqueue(.{ .char = 0x1b }),
                    else => self.handleEscape(),
                }
                self.enqueue(.{ .char = c });
            },
            .timeout => self.handleEscape(),
            .shutdown => {},
        }
    }

    fn run(self: *Self) void {
        while (!self.shutdown.isSet()) {
            switch (self.read(null)) {
                .input => |i| {
                    switch (i catch unreachable) {
                        0x1b => self.maybeEscape(),
                        else => |c| self.enqueue(.{ .char = c }),
                    }
                },
                .timeout => unreachable,
                .shutdown => {},
            }
        }
    }

    pub fn stop(self: *Self) void {
        assert(self.worker != null);
        self.shutdown.set(self.io);
        self.worker.?.join();
        self.worker = null;
        self.shutdown.reset();
    }

    pub fn start(self: *Self) !void {
        assert(self.worker == null);
        assert(!self.shutdown.isSet());
        self.worker = try std.Thread.spawn(.{}, run, .{self});
    }

    pub fn trapEscape(self: *Self, trap: bool) void {
        self.trap_escape = trap;
    }

    fn falliblePoll(self: *Self, timeout: ?Io.Duration) error{
        Canceled,
        ConcurrencyUnavailable,
        Closed,
    }!InputEvent {
        const Result = union(enum) {
            input: error{ Canceled, Closed }!InputEvent,
            timeout: error{Canceled}!void,
            escape: error{Canceled}!void,
        };
        var results: [3]Result = undefined;
        var select = Io.Select(Result).init(self.io, &results);
        defer _ = select.cancel();

        try select.concurrent(.input, InputQueue.getOne, .{ &self.queue, self.io });
        try select.concurrent(.escape, Io.Event.wait, .{ self.escape_event, self.io });

        if (timeout) |t|
            try select.concurrent(.timeout, Io.Clock.Duration.sleep, .{
                .{ .raw = t, .clock = .awake },
                self.io,
            });

        return switch (try select.await()) {
            .input => |ev| try ev,
            .escape => .{ .escape = {} },
            .timeout => .{ .timeout = {} },
        };
    }

    pub fn poll(self: *Self, timeout: ?Io.Duration) InputEvent {
        return self.falliblePoll(timeout) catch unreachable;
    }
};

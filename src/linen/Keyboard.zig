const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const Self = @This();

io: Io,
reader: *Io.Reader,
escape_event: *Io.Event,
queue: Io.Queue(u8),
trap_escape: bool = true, // TODO atomic
shutdown: Io.Event = .unset,
worker: ?std.Thread = null,

const ReadResult = union(enum) {
    input: error{ EndOfStream, ReadFailed }!u8,
    timeout: error{Canceled}!void,
    shutdown: error{Canceled}!void,
};

pub fn init(io: Io, reader: *Io.Reader, buffer: []u8, escape_event: *Io.Event) Self {
    return Self{
        .io = io,
        .reader = reader,
        .queue = .init(buffer),
        .escape_event = escape_event,
    };
}

fn fallibleRead(self: *Self, timeout: ?Io.Duration) !ReadResult {
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

fn read(self: *Self, timeout: ?Io.Duration) ReadResult {
    return self.fallibleRead(timeout) catch unreachable;
}

fn enqueue(self: *Self, c: u8) void {
    self.queue.putOne(self.io, c) catch unreachable;
}

fn handleEscape(self: *Self) void {
    if (self.trap_escape)
        self.escape_event.set(self.io)
    else
        self.enqueue(0x1b);
}

fn maybeEscape(self: *Self) void {
    switch (self.read(.fromMilliseconds(10))) {
        .input => |i| {
            const c = i catch unreachable;
            switch (c) {
                '[' => self.enqueue(0x1b),
                else => self.handleEscape(),
            }
            self.enqueue(c);
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
                    else => |c| self.enqueue(c),
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
    self.worker = try std.Thread.spawn(.{}, run, .{self});
}

pub fn trapEscape(self: *Self, trap: bool) void {
    self.trap_escape = trap;
}

const PollResult = union(enum) { input: u8, escape: void, timeout: void };

fn falliblePoll(self: *Self, timeout: ?Io.Duration) !PollResult {
    const Result = union(enum) {
        input: error{ Canceled, Closed }!u8,
        timeout: error{Canceled}!void,
        escape: error{Canceled}!void,
    };
    var results: [3]Result = undefined;
    var select = Io.Select(Result).init(self.io, &results);
    defer _ = select.cancel();

    try select.concurrent(.input, Io.Queue(u8).getOne, .{ &self.queue, self.io });
    try select.concurrent(.escape, Io.Event.wait, .{ self.escape_event, self.io });

    if (timeout) |t|
        try select.concurrent(.timeout, Io.Clock.Duration.sleep, .{
            .{ .raw = t, .clock = .awake },
            self.io,
        });

    return switch (try select.await()) {
        .input => |c| .{ .input = try c },
        .escape => .{ .escape = {} },
        .timeout => .{ .timeout = {} },
    };
}

pub fn poll(self: *Self, timeout: ?Io.Duration) PollResult {
    return self.falliblePoll(timeout) catch unreachable;
}

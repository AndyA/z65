const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const tools = @import("tools.zig");

const Self = @This();
const EscapeHandler = tools.Signal(anyopaque);

io: Io,
reader: *Io.Reader,
on_escape: EscapeHandler,
queue: Io.Queue(u8),
trap_escape: bool = true, // TODO atomic
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

fn infallibleRead(self: *Self, timeout: ?Io.Duration) ReadResult {
    return self.fallibleRead(timeout) catch unreachable;
}

fn enqueue(self: *Self, c: u8) void {
    self.queue.putOne(self.io, c) catch unreachable;
}

fn handleEscape(self: *Self) void {
    if (self.trap_escape) {
        self.on_escape.signal();
    } else {
        self.enqueue(0x1b);
    }
}

fn maybeEscape(self: *Self) void {
    switch (self.infallibleRead(.fromMilliseconds(10))) {
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
        switch (self.infallibleRead(null)) {
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
    self.shutdown.set(self.io);
}

pub fn start(self: *Self) !void {
    const t = try std.Thread.spawn(.{}, run, .{self});
    t.detach();
}

pub fn trapEscape(self: *Self, trap: bool) void {
    self.trap_escape = trap;
}

const PollError = error{ Canceled, Closed, ConcurrencyUnavailable };

pub fn poll(self: *Self, timeout: ?Io.Duration) ?u8 {
    const PollResult = union(enum) {
        input: error{ Canceled, Closed }!u8,
        timeout: error{Canceled}!void,
    };
    var results: [2]PollResult = undefined;
    var select = Io.Select(PollResult).init(self.io, &results);
    defer _ = select.cancel();

    select.concurrent(.input, Io.Queue(u8).getOne, .{ &self.queue, self.io }) catch unreachable;
    if (timeout) |t|
        select.concurrent(.timeout, Io.Clock.Duration.sleep, .{
            .{ .raw = t, .clock = .awake },
            self.io,
        }) catch unreachable;

    return switch (select.await() catch unreachable) {
        .input => |c| c catch unreachable,
        .timeout => null,
    };
}

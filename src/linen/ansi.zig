const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;

pub const InputMeta = enum(u8) {
    UP,
    DOWN,
    RIGHT,
    LEFT,
    END,
    HOME,
    INS,
    DEL,
    PGUP,
    PGDOWN,
    F0,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    F13,
    F14,
    F15,
    F16,
    F17,
    F18,
    F19,
    F20,
};

const ANSI_MAP = [_]struct { []const u8, InputMeta }{
    .{ "[A", .UP },
    .{ "[B", .DOWN },
    .{ "[C", .RIGHT },
    .{ "[D", .LEFT },
    .{ "[F", .END },
    .{ "[H", .HOME },
    .{ "[2~", .INS },
    .{ "[3~", .DEL },
    .{ "[5~", .PGUP },
    .{ "[6~", .PGDOWN },
    .{ "[10~", .F0 },
    .{ "[11~", .F1 },
    .{ "[12~", .F2 },
    .{ "[13~", .F3 },
    .{ "[14~", .F4 },
    .{ "[15~", .F5 },
    .{ "[17~", .F6 },
    .{ "[18~", .F7 },
    .{ "[19~", .F8 },
    .{ "[20~", .F9 },
    .{ "[21~", .F10 },
    .{ "[23~", .F11 },
    .{ "[24~", .F12 },
    .{ "[25~", .F13 },
    .{ "[26~", .F14 },
    .{ "[28~", .F15 },
    .{ "[29~", .F16 },
    .{ "[31~", .F17 },
    .{ "[32~", .F18 },
    .{ "[33~", .F19 },
    .{ "[34~", .F20 },
    .{ "OP", .F1 },
    .{ "OQ", .F2 },
    .{ "OR", .F3 },
    .{ "OS", .F4 },
};

pub const InputEvent = union(enum) {
    char: u8,
    meta: InputMeta,
    escape: void,
    timeout: void,
};

pub const Engine = struct {
    const Self = @This();
    const InputQueue = Io.Queue(InputEvent);

    io: Io,
    reader: *Io.Reader,
    writer: *Io.Writer,
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

    pub fn init(
        io: Io,
        reader: *Io.Reader,
        writer: *Io.Writer,
        buffer: []InputEvent,
        escape_event: *Io.Event,
    ) Self {
        return Self{
            .io = io,
            .reader = reader,
            .writer = writer,
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

    fn handleAnsi(self: *Self, seq: []const u8) void {
        // Look for simple matches
        for (ANSI_MAP) |im| {
            if (std.mem.eql(u8, im.@"0", seq)) {
                self.enqueue(.{ .meta = im.@"1" });
                return;
            }
        }
        // Handle sequence
        print("CMD: ", .{});
        for (seq) |c|
            print("{x:0>2} ", .{c});
        print("\"", .{});
        for (seq) |c|
            print("{c}", .{if (std.ascii.isPrint(c)) c else '.'});
        print("\"\n", .{});
    }

    fn parseEscape(self: *Self) void {
        const State = enum {
            const State = @This();

            initial,
            parameter,
            intermediate,
            final,

            fn isValid(st: State, c: u8) bool {
                return switch (st) {
                    .initial => c >= 0x40 and c <= 0x5f,
                    .parameter => c >= 0x30 and c <= 0x3f,
                    .intermediate => c >= 0x20 and c <= 0x2f,
                    .final => c >= 0x40 and c <= 0x7e,
                };
            }

            fn next(st: State) State {
                return switch (st) {
                    .initial => .parameter,
                    .parameter => .intermediate,
                    .intermediate => .final,
                    .final => unreachable,
                };
            }
        };

        var state: State = .initial;
        var buf: [256]u8 = undefined;
        var buf_pos: u16 = 0;

        esc: while (true) {
            switch (self.read(.fromMilliseconds(10))) {
                .input => |i| {
                    const c = i catch unreachable;

                    if (buf_pos == buf.len) break :esc;

                    buf[buf_pos] = c;
                    buf_pos += 1;

                    decode: switch (state) {
                        .initial => {
                            if (!state.isValid(c)) break :esc;
                            state = state.next();
                        },
                        .parameter, .intermediate => {
                            if (!state.isValid(c)) {
                                state = state.next();
                                continue :decode state;
                            }
                        },
                        .final => {
                            if (!state.isValid(c)) break :esc;
                            self.handleAnsi(buf[0..buf_pos]);
                            return;
                        },
                    }
                },
                .timeout, .shutdown => break :esc,
            }
        }

        // If we leave the loop decode failed so handle Escape and send any
        // additional bytes
        self.handleEscape();
        for (buf[0..buf_pos]) |c|
            self.enqueue(.{ .char = c });
    }

    fn run(self: *Self) void {
        while (!self.shutdown.isSet()) {
            switch (self.read(null)) {
                .input => |i| {
                    switch (i catch unreachable) {
                        0x1b => self.parseEscape(),
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

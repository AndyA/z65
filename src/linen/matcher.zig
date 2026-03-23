const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const Allocator = std.mem.Allocator;

const Atom = union(enum) {
    const Self = @This();

    literal: u8,
    charset: u256,
    capture_start,
    capture_end,

    pub fn eql(self: Self, other: Self) bool {
        if (@intFromEnum(self) != @intFromEnum(other))
            return false;
        return switch (self) {
            .literal => |v| v == other.literal,
            .charset => |v| v == other.charset,
            else => true,
        };
    }
};

const Token = struct {
    const Self = @This();

    quantifier: enum { @"?", @"*", @"1", @"+" },

    atom: Atom,

    pub fn eql(self: Self, other: Self) bool {
        return self.quantifier == other.quantifier and
            self.atom.eql(other.atom);
    }
};

fn makeCharset(range: []const u8) u256 {
    var set: u256 = 0;
    var flip = false;
    var span = false;
    var last_c: ?u8 = null;

    for (range) |nc| {
        if (set == 0 and nc == '~') {
            flip = !flip;
            continue;
        }
        if (nc == '-') {
            span = true;
        } else {
            if (span) {
                if (last_c) |lc| {
                    var c = lc + 1;
                    while (c <= nc) : (c += 1)
                        set |= @as(u256, 1) << c;
                    last_c = null;
                } else {
                    set |= @as(u256, 1) << '-';
                }
                span = false;
            } else {
                last_c = nc;
                set |= @as(u256, 1) << nc;
            }
        }
    }

    if (span)
        set |= @as(u256, 1) << '-';

    return if (flip) ~set else set;
}

const TokenIter = struct {
    const Self = @This();

    source: []const u8,
    pos: u32 = 0,

    pub fn init(source: []const u8) Self {
        return Self{ .source = source };
    }

    fn peekChar(self: Self) ?u8 {
        assert(self.pos <= self.source.len);
        if (self.pos < self.source.len)
            return self.source[self.pos];
        return null;
    }

    fn nextChar(self: *Self) ?u8 {
        assert(self.pos <= self.source.len);
        if (self.pos < self.source.len) {
            defer self.pos += 1;
            return self.source[self.pos];
        }
        return null;
    }

    fn needChar(self: *Self) !u8 {
        if (self.nextChar()) |nc| return nc;
        return error.BadRegex;
    }

    pub fn next(self: *Self) !?Token {
        if (self.nextChar()) |nc| {
            const atom = atom: switch (nc) {
                '\\' => {
                    break :atom switch (try self.needChar()) {
                        'd' => Atom{ .charset = makeCharset("0-9") },
                        else => |lit| Atom{ .literal = lit },
                    };
                },
                '(' => Atom{ .capture_start = {} },
                ')' => Atom{ .capture_end = {} },
                '.' => Atom{ .charset = std.math.maxInt(u256) },
                else => Atom{ .literal = nc },
            };

            // Check for modifiers
            if (self.peekChar()) |mc| {
                switch (mc) {
                    '?', '+', '*' => {
                        _ = self.nextChar();
                        return switch (mc) {
                            '?' => Token{ .atom = atom, .quantifier = .@"?" },
                            '*' => Token{ .atom = atom, .quantifier = .@"*" },
                            '+' => Token{ .atom = atom, .quantifier = .@"+" },
                            else => unreachable,
                        };
                    },
                    else => {},
                }
            }

            return Token{ .atom = atom, .quantifier = .@"1" };
        }

        return null;
    }
};

test TokenIter {
    var iter: TokenIter = .init("\x1b[(-?\\d+);(-?\\d+)R");
    const want = &[_]Token{
        .{ .quantifier = .@"1", .atom = .{ .literal = '\x1b' } },
        .{ .quantifier = .@"1", .atom = .{ .literal = '[' } },
        .{ .quantifier = .@"1", .atom = .{ .capture_start = {} } },
        .{ .quantifier = .@"?", .atom = .{ .literal = '-' } },
        .{ .quantifier = .@"+", .atom = .{ .charset = 0x3ff000000000000 } },
        .{ .quantifier = .@"1", .atom = .{ .capture_end = {} } },
        .{ .quantifier = .@"1", .atom = .{ .literal = ';' } },
        .{ .quantifier = .@"1", .atom = .{ .capture_start = {} } },
        .{ .quantifier = .@"?", .atom = .{ .literal = '-' } },
        .{ .quantifier = .@"+", .atom = .{ .charset = 0x3ff000000000000 } },
        .{ .quantifier = .@"1", .atom = .{ .capture_end = {} } },
        .{ .quantifier = .@"1", .atom = .{ .literal = 'R' } },
    };
    var pos: usize = 0;
    while (try iter.next()) |tok| : (pos += 1) {
        try expectEqualDeep(want[pos], tok);
    }
    try expectEqual(want.len, pos);
}

const MaxCaptures: usize = 10;
const CaptureCapacity: usize = 1024;

const Context = struct {
    const Self = @This();

    capturing: bool = false,

    buf: [CaptureCapacity]u8 = undefined,
    buf_pos: usize = 0,
    capture_start: usize = 0,

    capture: [MaxCaptures][]const u8 = undefined,
    capture_pos: usize = 0,

    pub fn startCapture(self: *Self) !void {
        assert(!self.capturing);
        if (self.capture_pos == MaxCaptures)
            return error.CaptureOverflow;
        self.capturing = true;
        self.capture_start = self.buf_pos;
    }

    pub fn stopCapture(self: *Self) void {
        assert(self.capturing);
        assert(self.capture_pos < CaptureCapacity);
        self.capture[self.capture_pos] = self.buf[self.capture_start..self.buf_pos];
        self.capture_pos += 1;
        self.capturing = false;
    }

    pub fn observe(self: *Self, char: u8) !void {
        if (self.capturing) {
            if (self.buf_pos == CaptureCapacity)
                return error.CaptureOverflow;
            self.buf[self.buf_pos] = char;
            self.buf_pos += 1;
        }
    }

    pub fn captures(self: *const Self) []const []const u8 {
        assert(!self.capturing);
        return self.capture[0..self.capture_pos];
    }
};

test Context {
    var c = Context{};
    for ("Hello ") |char|
        try c.observe(char);

    try c.startCapture();
    for ("World") |char|
        try c.observe(char);
    c.stopCapture();

    for (" Again") |char|
        try c.observe(char);

    try c.startCapture();
    for (".") |char|
        try c.observe(char);
    c.stopCapture();

    for ("!") |char|
        try c.observe(char);

    const caps = c.captures();
    try expectEqual(2, caps.len);
    try expectEqualDeep("World", caps[0]);
    try expectEqualDeep(".", caps[1]);
}

fn Terminal(comptime T: type) type {
    return struct {
        outcome: T,
        captures: []const []const u8,
    };
}

fn MatchState(comptime T: type) type {
    return union(u8) {
        const Self = @This();
        next: *const fn (self: *Self, ctx: *Context, char: u8) Self,
        terminal: Terminal(T),
        failed,
    };
}

test MatchState {}

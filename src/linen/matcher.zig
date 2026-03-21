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

pub fn MatchState(comptime T: type) type {
    return union(u8) {
        const Self = @This();
        next: *const fn (self: *Self, char: u8) Self,
        terminal: T,
        failed,
    };
}

test MatchState {
    // const
}

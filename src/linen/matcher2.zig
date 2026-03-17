const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const Allocator = std.mem.Allocator;

const RegexAtom = union(enum) {
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

const RegexToken = struct {
    const Self = @This();

    quantifier: enum {
        @"?",
        @"*",
        @"1",
        @"+",
    },

    atom: RegexAtom,

    pub fn eql(self: Self, other: Self) bool {
        return self.quantifier == other.quantifier and
            self.atom.eql(other.atom);
    }
};

const RegexIter = struct {
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

    pub fn makeCharset(range: []const u8) u256 {
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

    pub fn next(self: *Self) !?RegexToken {
        if (self.nextChar()) |nc| {
            const atom = atom: switch (nc) {
                '\\' => {
                    break :atom switch (try self.needChar()) {
                        'd' => RegexAtom{ .charset = makeCharset("0-9") },
                        else => |lit| RegexAtom{ .literal = lit },
                    };
                },
                '(' => RegexAtom{ .capture_start = {} },
                ')' => RegexAtom{ .capture_end = {} },
                '.' => RegexAtom{ .charset = std.math.maxInt(u256) },
                else => RegexAtom{ .literal = nc },
            };

            // Check for modifiers
            if (self.peekChar()) |mc| {
                switch (mc) {
                    '?', '+', '*' => {
                        _ = self.nextChar();
                        return switch (mc) {
                            '?' => RegexToken{ .atom = atom, .quantifier = .@"?" },
                            '*' => RegexToken{ .atom = atom, .quantifier = .@"*" },
                            '+' => RegexToken{ .atom = atom, .quantifier = .@"+" },
                            else => unreachable,
                        };
                    },
                    else => {},
                }
            }

            return RegexToken{ .atom = atom, .quantifier = .@"1" };
        }

        return null;
    }
};

test RegexIter {
    var iter: RegexIter = .init("\x1b[(-?\\d+);(-?\\d+)R");
    const want = &[_]RegexToken{
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

pub fn MatchClause(comptime T: type) type {
    return struct {
        re: []const u8,
        outcome: T,
    };
}

pub fn MatchState(comptime T: type) type {
    return union(enum) {
        const Self = @This();

        advance: fn (char: u8, slot: *MatchState(T)) void,
        outcome: T,
        failed,

        pub fn step(self: Self, char: u8) Self {
            switch (self) {
                .advance => |adv| {
                    const next = Self{ .failed = {} };
                    adv(char, &next);
                    return next;
                },
                else => unreachable,
            }
        }
    };
}

fn stepper(
    comptime T: type,
    comptime tokens: []const []const RegexToken,
    comptime depth: usize,
    comptime outcomes: []const T,
) MatchState(T) {
    comptime {
        const MS = MatchState(T);

        var terminals: usize = 0;
        for (tokens) |tok| {
            if (tok.len == depth)
                terminals += 1;
        }

        if (terminals > 0) {
            assert(terminals == 1);
            assert(tokens.len == 1);
            return .{ .outcome = outcomes[0] };
        }

        const shim = struct {
            fn match(
                char: u8,
                slot: *MS,
                comptime tok: RegexToken,
                comptime from: usize,
                comptime to: usize,
            ) void {
                const matched = switch (tok.atom) {
                    .literal => |lit| lit == char,
                    .charset => |cs| (cs & (@as(u256, 1) << char)) != 0,
                    else => unreachable,
                };
                if (matched) {
                    switch (tok.quantifier) {
                        .@"1" => {
                            slot.* = stepper(T, tokens[from..to], depth + 1, outcomes[from..to]);
                            return;
                        },
                    }
                } else {}
                unreachable;
            }

            pub fn advance(char: u8, slot: *MS) void {
                var start: ?struct { t: RegexToken, i: u32 } = null;
                inline for (tokens, 0..) |t, i| {
                    if (start) |st| {
                        if (st.t.eql(t))
                            continue;
                        match(char, slot, st.t, st.i, i);
                        if (slot.* != .failed)
                            return;
                    }
                    start = .{ .t = t, .i = i };
                }

                match(char, slot, start.?.t, start.?.i, tokens.len);
            }
        };

        return .{ .advance = shim.advance };
    }
}

pub fn Matcher(comptime T: type, comptime clauses: []const MatchClause(T)) MatchState(T) {
    comptime {
        const MC = MatchClause(T);

        const ordered: [clauses.len]MC = blk: {
            var ordered: [clauses.len]MC = undefined;
            for (clauses, 0..) |c, i| ordered[i] = c;
            const Context = struct {
                pub fn lt(_: @This(), lhs: MC, rhs: MC) bool {
                    return std.mem.order(u8, lhs.re, rhs.re) == .lt;
                }
            };
            std.mem.sort(MC, &ordered, Context{}, Context.lt);
            break :blk ordered;
        };

        const token_count: usize, const token_counts: [clauses.len]usize = blk: {
            var token_count: usize = 0;
            var token_counts: [clauses.len]usize = undefined;
            for (ordered, 0..) |c, i| {
                var iter: RegexIter = .init(c.re);
                token_counts[i] = 0;
                while (iter.next() catch @compileError("Bad regex")) |_| {
                    token_count += 1;
                    token_counts[i] += 1;
                }
            }
            break :blk .{ token_count, token_counts };
        };

        const store: [token_count]RegexToken = blk: {
            var store: [token_count]RegexToken = undefined;
            var store_pos: usize = 0;
            for (ordered) |c| {
                var iter: RegexIter = .init(c.re);
                while (iter.next() catch @compileError("Bad regex")) |tok| {
                    store[store_pos] = tok;
                    store_pos += 1;
                }
            }
            break :blk store;
        };

        const outcomes: [clauses.len]T = blk: {
            var outcomes: [clauses.len]T = undefined;
            for (clauses, 0..) |c, i|
                outcomes[i] = c.outcome;

            break :blk outcomes;
        };

        const tokens: [clauses.len][]const RegexToken = blk: {
            var tokens: [clauses.len][]const RegexToken = undefined;
            var store_pos: usize = 0;
            for (0..clauses.len) |i| {
                const next_pos = store_pos + token_counts[i];
                defer store_pos = next_pos;
                tokens[i] = store[store_pos..next_pos];
            }
            assert(store_pos == token_count);
            break :blk tokens;
        };

        return stepper(T, &tokens, 0, &outcomes);
    }
}

test Matcher {
    const Outcome = enum {
        CURSOR_POS_REPORT,
        UP,
        DOWN,
        RIGHT,
        LEFT,
    };
    const clauses = &[_]MatchClause(Outcome){
        .{ .re = "\x1b[A", .outcome = .UP },
        .{ .re = "\x1b[B", .outcome = .DOWN },
        .{ .re = "\x1b[C", .outcome = .RIGHT },
        .{ .re = "\x1b[D", .outcome = .LEFT },
        .{ .re = "\x1b[(-?\\d+);(-?\\d+)R", .outcome = .CURSOR_POS_REPORT },
    };

    const M = Matcher(Outcome, clauses[0..]);
    _ = M;
}

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const Allocator = std.mem.Allocator;

const RegexAtom = union(enum) {
    const Self = @This();
    literal: u8,
    optional: *const Self,
    zero_or_more: *const Self,
    one_or_more: *const Self,
    charset: u256,
    capture_start,
    capture_end,

    pub fn dupe(self: Self, gpa: Allocator) !*const Self {
        const next = try gpa.create(Self);
        next.* = self;
        return next;
    }

    pub fn deinit(self: Self, gpa: Allocator) void {
        switch (self) {
            .optional, .zero_or_more, .one_or_more => |next| {
                next.deinit(gpa);
                gpa.destroy(next);
            },
            else => {},
        }
    }

    pub fn eql(self: Self, other: Self) bool {
        if (@intFromEnum(self) != @intFromEnum(other))
            return false;
        return switch (self) {
            .literal => |c| other.literal == c,
            .optional => |w| w.eql(other.optional),
            .zero_or_more => |w| w.eql(other.zero_or_more),
            .one_or_more => |w| w.eql(other.one_or_more),
            .charset => |c| c == other.charset,
            else => true,
        };
    }
};

test {
    const gpa = std.testing.allocator;
    const atom = RegexAtom{ .literal = 'A' };
    defer atom.deinit(gpa);

    try expectEqual('A', atom.literal);

    const wrap = try gpa.create(RegexAtom);
    errdefer gpa.destroy(wrap);

    wrap.* = atom;
    const opt = RegexAtom{ .optional = wrap };
    defer opt.deinit(gpa);
}

test "comptime" {
    comptime {
        var buffer: [4096]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .init(&buffer);
        const gpa = fba.allocator();
        const foo = try gpa.dupe(u8, "Hello!");
        defer gpa.free(foo);
    }
}

const RegexIter = struct {
    const Self = @This();

    gpa: Allocator,
    source: []const u8,
    pos: u32 = 0,

    pub fn init(gpa: Allocator, source: []const u8) Self {
        return Self{ .gpa = gpa, .source = source };
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

    fn makeCharset(chars: []const u8) u256 {
        var set: u256 = 0;
        for (chars) |c| {
            set |= @as(u256, 1) << c;
        }
        return set;
    }

    pub fn next(self: *Self) !?RegexAtom {
        if (self.nextChar()) |nc| {
            const tok = tok: switch (nc) {
                '\\' => {
                    if (self.nextChar()) |dc| {
                        break :tok switch (dc) {
                            'd' => RegexAtom{ .charset = makeCharset("0123456789") },
                            else => RegexAtom{ .literal = dc },
                        };
                    }
                    return error.BadRegex;
                },
                '(' => RegexAtom{ .capture_start = {} },
                ')' => RegexAtom{ .capture_end = {} },
                else => RegexAtom{ .literal = nc },
            };

            // Check for modifiers
            if (self.peekChar()) |mc| {
                switch (mc) {
                    '?', '+', '*' => {
                        _ = self.nextChar();
                        const wrapped = try tok.dupe(self.gpa);
                        return switch (mc) {
                            '?' => RegexAtom{ .optional = wrapped },
                            '*' => RegexAtom{ .zero_or_more = wrapped },
                            '+' => RegexAtom{ .one_or_more = wrapped },
                            else => unreachable,
                        };
                    },
                    else => {},
                }
            }

            return tok;
        }

        return null;
    }
};

test RegexIter {
    const gpa = std.testing.allocator;
    var iter: RegexIter = .init(gpa, "\x1b[(-?\\d+);(-?\\d+)R");
    const want = &[_]RegexAtom{
        .{ .literal = '\x1b' },
        .{ .literal = '[' },
        .{ .capture_start = {} },
        .{ .optional = &.{ .literal = '-' } },
        .{ .one_or_more = &.{ .charset = 0x3ff000000000000 } },
        .{ .capture_end = {} },
        .{ .literal = ';' },
        .{ .capture_start = {} },
        .{ .optional = &.{ .literal = '-' } },
        .{ .one_or_more = &.{ .charset = 0x3ff000000000000 } },
        .{ .capture_end = {} },
        .{ .literal = 'R' },
    };
    var pos: usize = 0;
    while (try iter.next()) |tok| : (pos += 1) {
        try expectEqualDeep(want[pos], tok);
        tok.deinit(gpa);
    }
}

pub fn MatchClause(comptime T: type) type {
    return struct {
        re: []const u8,
        outcome: T,
    };
}

pub fn MatchState(comptime T: type) type {
    return union(enum) {
        step: fn (gpa: Allocator, char: u8) *MatchState(T),
        outcome: T,
        failed,
    };
}

fn matcher(
    comptime T: type,
    comptime token: RegexAtom,
    comptime iters: []RegexIter,
    comptime outcomes: []T,
    gpa: Allocator,
    char: u8,
) MatchState(T) {
    _ = gpa;
    const failed: MatchState(T) = .{ .failed = {} };
    const next_state = stepper(T, iters, outcomes);
    return switch (token) {
        .literal => |c| if (char == c) next_state else failed,
        else => unreachable,
    };
}

fn stepper(
    comptime T: type,
    comptime iters: []RegexIter,
    comptime outcomes: []T,
) MatchState(T) {
    comptime {
        const MS = MatchState(T);
        var tokens: [iters.len]?RegexAtom = undefined;
        var terminals: u32 = 0;
        for (iters, 0..) |*iter, i| {
            if (iter.next() catch unreachable) |t| {
                tokens[i] = t;
            } else {
                terminals += 1;
            }
        }

        if (terminals > 0) {
            assert(terminals == 1);
            assert(iters.len == 1);
            return .{ .outcome = outcomes[0] };
        }

        defer {
            for (tokens, 0..) |t, i| t.deinit(iters[i].gpa);
        }

        const toks = tokens[0..];

        const shim = struct {
            pub fn step(gpa: Allocator, char: u8) *MS {
                var start: ?struct { t: RegexAtom, i: u32 } = null;
                inline for (toks, 0..) |t, i| {
                    if (start) |st| {
                        if (st.t.eql(t)) continue;
                        // found a change
                        const next_state = matcher(
                            T,
                            st.t,
                            iters[st.i..i],
                            outcomes[st.i..i],
                            gpa,
                            char,
                        );
                        if (next_state != .failed)
                            return next_state;
                    }
                    start = .{ .t = t, .i = i };
                }
            }
        };

        return .{ .step = shim.step };
    }
}

pub fn Matcher(comptime T: type, comptime clauses: []const MatchClause(T)) MatchState(T) {
    comptime {
        const MC = MatchClause(T);

        var buffer: [@sizeOf(RegexAtom) * clauses.len * 5]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .init(&buffer);
        const gpa = fba.allocator();

        var ordered: [clauses.len]MC = undefined;
        for (clauses, 0..) |c, i| ordered[i] = c;
        const Context = struct {
            pub fn lt(_: @This(), lhs: MC, rhs: MC) bool {
                return std.mem.order(u8, lhs.re, rhs.re) == .lt;
            }
        };
        std.mem.sort(MC, &ordered, Context{}, Context.lt);

        var iters: [clauses.len]RegexIter = undefined;
        var outcomes: [clauses.len]T = undefined;
        for (ordered, 0..) |c, i| {
            iters[i] = .init(gpa, c.re);
            outcomes[i] = c.outcome;
        }

        const ii = iters[0..];
        const oo = outcomes[0..];

        return stepper(T, ii, oo);
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

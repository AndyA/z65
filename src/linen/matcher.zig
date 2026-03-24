const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const Allocator = std.mem.Allocator;

const Token = struct {
    const Self = @This();
    pub const Quantifier = enum { @"?", @"*", @"1", @"+" };
    pub const Capture = enum { nop, start, stop };

    charset: u256,
    quantifier: Quantifier = .@"1",
    capture: Capture = .nop,

    pub fn eql(self: Self, other: Self) bool {
        return self.quantifier == other.quantifier and
            self.capture == other.capture and
            self.charset == other.charset;
    }

    pub fn match(self: Self, char: u8) bool {
        return (self.charset & @as(u256, 1) << char) != 0;
    }
};

fn spotCharset(char: u8) u256 {
    return @as(u256, 1) << char;
}

fn rangeCharset(range: []const u8) u256 {
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
        if (self.nextChar()) |next_char| {
            var nc = next_char;
            const capture: Token.Capture =
                cap: switch (nc) {
                    '(', ')' => {
                        const cap: Token.Capture = if (nc == '(') .start else .stop;
                        nc = try self.needChar();
                        break :cap cap;
                    },
                    else => .nop,
                };

            const charset = charset: switch (nc) {
                '\\' => {
                    break :charset switch (try self.needChar()) {
                        'd' => rangeCharset("0-9"),
                        else => |lit| spotCharset(lit),
                    };
                },
                '.' => std.math.maxInt(u256),
                else => spotCharset(nc),
            };

            // Check for modifiers
            if (self.peekChar()) |mc| {
                switch (mc) {
                    '?', '+', '*' => {
                        _ = self.nextChar();
                        const quantifier: Token.Quantifier = switch (mc) {
                            '?' => .@"?",
                            '*' => .@"*",
                            '+' => .@"+",
                            else => unreachable,
                        };
                        return Token{
                            .capture = capture,
                            .charset = charset,
                            .quantifier = quantifier,
                        };
                    },
                    else => {},
                }
            }

            return Token{
                .capture = capture,
                .charset = charset,
                .quantifier = .@"1",
            };
        }

        return null;
    }
};

test TokenIter {
    var iter: TokenIter = .init("\x1b\\[(-?\\d+);(-?\\d+)R");
    const want = &[_]Token{
        .{ .charset = spotCharset('\x1b') },
        .{ .charset = spotCharset('[') },
        .{ .charset = spotCharset('-'), .quantifier = .@"?", .capture = .start },
        .{ .charset = rangeCharset("0-9"), .quantifier = .@"+" },
        .{ .charset = spotCharset(';'), .capture = .stop },
        .{ .charset = spotCharset('-'), .quantifier = .@"?", .capture = .start },
        .{ .charset = rangeCharset("0-9"), .quantifier = .@"+" },
        .{ .charset = spotCharset('R'), .capture = .stop },
    };
    var pos: usize = 0;
    while (try iter.next()) |tok| : (pos += 1) {
        try expectEqualDeep(want[pos], tok);
    }
    try expectEqual(want.len, pos);
}

pub fn MatchContext(comptime max_captures: usize, comptime capture_capacity: usize) type {
    return struct {
        const Self = @This();

        capturing: bool = false,

        buf: [capture_capacity]u8 = undefined,
        buf_pos: usize = 0,
        capture_start: usize = 0,

        capture: [max_captures][]const u8 = undefined,
        capture_pos: usize = 0,

        pub fn startCapture(self: *Self) !void {
            assert(!self.capturing);
            if (self.capture_pos == max_captures)
                return error.CaptureOverflow;
            self.capturing = true;
            self.capture_start = self.buf_pos;
        }

        pub fn stopCapture(self: *Self) void {
            assert(self.capturing);
            assert(self.capture_pos < capture_capacity);
            self.capture[self.capture_pos] = self.buf[self.capture_start..self.buf_pos];
            self.capture_pos += 1;
            self.capturing = false;
        }

        pub fn observe(self: *Self, char: u8) !void {
            if (self.capturing) {
                if (self.buf_pos == capture_capacity)
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
}

test MatchContext {
    var c = MatchContext(10, 1024){};
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

pub fn MatchClause(comptime T: type) type {
    return struct {
        re: []const u8,
        outcome: T,
    };
}

fn TrieNode(comptime T: type) type {
    return union(enum) {
        const Self = @This();
        next: struct { token: Token, children: []const Self },
        terminal: T,
    };
}

fn buildTree(
    comptime T: type,
    comptime exprs: []const []const Token,
    comptime outcomes: []const T,
) []const TrieNode(T) {
    comptime {
        // Count distinct prefixes
        const distinct: usize = blk: {
            var count: usize = 0;
            var prev: ?Token = null;
            for (exprs) |ex| {
                if (ex.len == 0) {
                    assert(exprs.len == 1); // must be the only one
                    const term = term: {
                        var term: [1]TrieNode(T) = undefined;
                        term[0] = .{ .terminal = outcomes[0] };
                        break :term term;
                    };
                    return term[0..];
                }
                const tok = ex[0];
                if (prev == null or !prev.?.eql(tok)) {
                    count += 1;
                    prev = tok;
                }
            }
            break :blk count;
        };

        // Find the span of each distinct prefix
        const spans: [distinct]usize = blk: {
            var spans: [distinct]usize = undefined;
            var span_pos: usize = 0;

            var prev: ?Token = null;
            var run_length: usize = 0;
            for (exprs) |ex| {
                assert(ex.len != 0);
                const tok = ex[0];
                if (prev != null and !prev.?.eql(tok)) {
                    spans[span_pos] = run_length;
                    run_length = 1;
                    span_pos += 1;
                } else {
                    run_length += 1;
                    prev = tok;
                }
            }
            if (run_length != 0) {
                spans[span_pos] = run_length;
                span_pos += 1;
            }
            assert(span_pos == distinct);
            break :blk spans;
        };

        // Recursively build tree
        const nodes: [distinct]TrieNode(T) = blk: {
            var nodes: [distinct]TrieNode(T) = undefined;
            var node_pos: usize = 0;
            var expr_pos: usize = 0;
            for (spans) |span| {
                var child_exprs: [span][]const Token = undefined;
                for (0..span, expr_pos..) |i, e| {
                    child_exprs[i] = exprs[e][1..];
                }
                nodes[node_pos] = .{ .next = .{
                    .token = exprs[expr_pos][0],
                    .children = buildTree(
                        T,
                        child_exprs[0..],
                        outcomes[expr_pos .. expr_pos + span],
                    ),
                } };
                node_pos += 1;
                expr_pos += span;
            }
            assert(node_pos == distinct);
            break :blk nodes;
        };

        return nodes[0..];
    }
}

fn matchTree(
    comptime T: type,
    comptime clauses: []const MatchClause(T),
) []const TrieNode(T) {
    comptime {
        const MC = MatchClause(T);

        // Sort the clauses lexically
        const ordered: [clauses.len]MC = blk: {
            var ordered: [clauses.len]MC = undefined;
            for (clauses, 0..) |c, i| ordered[i] = c;
            const Ctx = struct {
                pub fn lt(_: @This(), lhs: MC, rhs: MC) bool {
                    return std.mem.order(u8, lhs.re, rhs.re) == .lt;
                }
            };
            std.mem.sort(MC, &ordered, Ctx{}, Ctx.lt);
            break :blk ordered;
        };

        // Count the total number of tokens and the number per clause.
        const token_count: usize, const token_counts: [clauses.len]usize = blk: {
            var token_count: usize = 0;
            var token_counts: [clauses.len]usize = undefined;
            for (ordered, 0..) |c, i| {
                var iter: TokenIter = .init(c.re);
                token_counts[i] = 0;
                while (iter.next() catch @compileError("Bad regex")) |_| {
                    token_count += 1;
                    token_counts[i] += 1;
                }
            }
            break :blk .{ token_count, token_counts };
        };

        // Fetch the tokens into a const array
        const store: [token_count]Token = blk: {
            var store: [token_count]Token = undefined;
            var store_pos: usize = 0;
            for (ordered) |c| {
                var iter: TokenIter = .init(c.re);
                while (iter.next() catch @compileError("Bad regex")) |tok| {
                    store[store_pos] = tok;
                    store_pos += 1;
                }
            }
            break :blk store;
        };

        // The outcome for each clause
        const outcomes: [clauses.len]T = blk: {
            var outcomes: [clauses.len]T = undefined;
            for (clauses, 0..) |c, i|
                outcomes[i] = c.outcome;

            break :blk outcomes;
        };

        // The exprs for each clause
        const exprs: [clauses.len][]const Token = blk: {
            var exprs: [clauses.len][]const Token = undefined;
            var pos: usize = 0;
            for (0..clauses.len) |i| {
                const next_pos = pos + token_counts[i];
                defer pos = next_pos;
                exprs[i] = store[pos..next_pos];
            }
            assert(pos == token_count);
            break :blk exprs;
        };

        return buildTree(T, &exprs, &outcomes);
    }
}

test matchTree {
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

    comptime {
        // Just make sure it compiles...
        const mt = matchTree(Outcome, clauses[0..]);
        _ = mt;
    }
}

fn Terminal(comptime T: type) type {
    return struct {
        outcome: T,
        captures: []const []const u8,
    };
}

const MatchError = error{CaptureOverflow};

fn MatchState(comptime T: type, comptime Context: type) type {
    return union(enum) {
        const Self = @This();
        next: *const fn (ctx: *Context, char: u8) MatchError!Self,
        terminal: Terminal(T),
        failed,
    };
}

test MatchState {}

fn makeMatcher(
    comptime T: type,
    comptime Context: type,
    comptime trie: []const TrieNode(T),
) MatchState(T, Context) {
    comptime {
        const MS = MatchState(T, Context);
        if (trie.len == 1 and trie[0] == .terminal) {
            const shim = struct {
                pub fn next(ctx: *Context, _: u8) MatchError!MS {
                    return .{ .terminal = .{
                        .outcome = trie[0].terminal,
                        .captures = ctx.captures(),
                    } };
                }
            };

            return .{ .next = shim.next };
        } else {
            const next_child: [trie.len]MS = nc: {
                var kids: [trie.len]MS = undefined;
                for (trie, 0..) |node, i| {
                    kids[i] = makeMatcher(T, Context, node.next.children);
                }
                break :nc kids;
            };

            const star_child: [trie.len]MS = sc: {
                var kids: [trie.len]MS = undefined;
                for (trie, 0..) |node, i| {
                    var tmp: [1]TrieNode(T) = undefined;
                    tmp[0] = .{ .next = .{
                        .token = .{
                            .charset = node.next.token.charset,
                            .quantifier = .@"*",
                            .capture = .nop,
                        },
                        .children = node.next.children,
                    } };
                    kids[i] = makeMatcher(T, Context, &tmp);
                }

                break :sc kids;
            };

            const shim = struct {
                fn applyCapture(ctx: *Context, tok: Token) MatchError!void {
                    switch (tok.capture) {
                        .start => try ctx.startCapture(),
                        .stop => ctx.stopCapture(),
                        .nop => {},
                    }
                }

                pub fn next(ctx: *Context, char: u8) MatchError!MS {
                    try ctx.observe(char);

                    inline for (trie, 0..) |node, i| {
                        if (node.next.token.match(char)) {
                            try applyCapture(ctx, node.next.token);
                            switch (node.next.token.quantifier) {
                                .@"1", .@"?" => {
                                    return next_child[i];
                                },
                                .@"*", .@"+" => {
                                    return star_child[i];
                                },
                            }
                        } else {
                            switch (node.next.token.quantifier) {
                                .@"*", .@"?" => {
                                    try applyCapture(ctx, node.next.token);
                                    return next_child[i].next(ctx, char);
                                },
                                else => {},
                            }
                        }
                    }

                    return .{ .failed = {} };
                }
            };

            return .{ .next = shim.next };
        }
    }
}

pub fn matcher(
    comptime T: type,
    comptime Context: type,
    comptime clauses: []const MatchClause(T),
) type {
    comptime {
        @setEvalBranchQuota(std.math.maxInt(u32));
        const trie = matchTree(T, clauses);
        return makeMatcher(T, Context, trie);
    }
}

test matcher {
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

    const Context = MatchContext(10, 1024);

    comptime {
        const m = matcher(Outcome, Context, clauses[0..]);
        _ = m;
    }
}

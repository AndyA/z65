const std = @import("std");

const TokenType = enum { Literal, Parameter, Word };

const Token = union(TokenType) {
    Literal: struct { value: []const u8 },
    Parameter: struct { name: []const u8, type_name: []const u8 },
    Word: struct { value: []const u8 },
};

const OptionalToken = struct {
    token: Token,
    optional: bool,
};

const ParseError = error{
    MissingBracket,
    MissingColon,
    BadParameter,
    BadSyntax,
    MissingQuote,
};

fn cleanCommand(cmd: []const u8) []const u8 {
    var pos: usize = 0;
    while (pos < cmd.len and cmd[pos] == '*')
        pos += 1;

    return cmd[pos..];
}

fn literalToken(value: []const u8, optional: bool) OptionalToken {
    return OptionalToken{
        .token = Token{ .Literal = .{ .value = value } },
        .optional = optional,
    };
}

fn wordToken(value: []const u8, optional: bool) OptionalToken {
    return OptionalToken{
        .token = Token{ .Word = .{ .value = value } },
        .optional = optional,
    };
}

fn parameterToken(name: []const u8, type_name: []const u8, optional: bool) OptionalToken {
    return OptionalToken{
        .token = Token{ .Parameter = .{ .name = name, .type_name = type_name } },
        .optional = optional,
    };
}

const Checker = fn (char: u8) bool;

fn sentinelChecker(comptime sentinel: u8) Checker {
    const shim = struct {
        pub fn check(c: u8) bool {
            return c != sentinel;
        }
    };
    return shim.check;
}

const Scanner = struct {
    const Self = @This();
    src: []const u8,
    pos: usize = 0,

    pub fn init(src: []const u8) Self {
        return Self{ .src = src };
    }

    pub fn eot(self: Self) bool {
        std.debug.assert(self.pos <= self.src.len);
        return self.pos == self.src.len;
    }

    pub fn peek(self: Self) u8 {
        std.debug.assert(!self.eot());
        return self.src[self.pos];
    }

    pub fn one(self: *Self) []const u8 {
        std.debug.assert(!self.eot());
        const ch = self.src[self.pos .. self.pos + 1];
        self.advance();
        return ch;
    }

    pub fn advance(self: *Self) void {
        std.debug.assert(!self.eot());
        self.pos += 1;
    }

    pub fn space(self: Self) bool {
        if (self.eot()) return false;
        return std.ascii.isWhitespace(self.src[self.pos]);
    }

    pub fn skipSpace(self: *Self) void {
        while (self.space())
            self.advance();
    }

    pub fn takeWhile(self: *Self, comptime checker: Checker) []const u8 {
        const start = self.pos;
        while (!self.eot() and checker(self.src[self.pos]))
            self.advance();
        return self.src[start..self.pos];
    }

    pub fn takeTail(self: *Self) []const u8 {
        const start = self.pos;
        self.pos = self.src.len;
        return self.src[start..];
    }

    pub fn span(self: *Self, comptime checker: Checker) ![]const u8 {
        const frag = self.takeWhile(checker);
        if (frag.len == 0)
            return ParseError.BadSyntax;
        return frag;
    }
};

// Would have been a tagged union - but they can't be zero filled ATM.
const AbsRel = struct {
    addr: u32,
    rel: bool,

    pub fn resolve(self: @This(), base: u32) u32 {
        return switch (self.rel) {
            false => self.addr,
            true => @intCast(base + self.addr),
        };
    }
};

const ParamDecoder = struct {
    const Self = @This();

    fn notWhitespace(c: u8) bool {
        return !std.ascii.isWhitespace(c);
    }

    pub fn @"[]u8"(src: *Scanner) ![]const u8 {
        if (!src.eot() and src.peek() == '"') {
            src.advance();
            const str = src.span(sentinelChecker('"'));
            if (src.eot() or src.peek() != '"')
                return ParseError.MissingQuote;
            src.advance();
            return str;
        }
        return src.span(notWhitespace);
    }

    pub fn @"[]u8*"(src: *Scanner) ![]const u8 {
        return src.takeTail();
    }

    pub fn @"u8"(src: *Scanner) !u8 {
        const num = try src.span(std.ascii.isDigit);
        return std.fmt.parseInt(u8, num, 10);
    }

    pub fn @"u32"(src: *Scanner) !u32 {
        const num = try src.span(std.ascii.isDigit);
        return std.fmt.parseInt(u32, num, 10);
    }

    pub fn u32x(src: *Scanner) !u32 {
        const num = try src.span(std.ascii.isHex);
        return std.fmt.parseInt(u32, num, 16);
    }

    pub fn u32xr(src: *Scanner) !AbsRel {
        if (!src.eot() and src.peek() == '+') {
            src.advance();
            src.skipSpace();
            return .{ .addr = try Self.u32x(src), .rel = true };
        }
        return .{ .addr = try Self.u32x(src), .rel = false };
    }
};

const Parser = struct {
    const Self = @This();
    opt_depth: usize = 0,
    scanner: Scanner,

    pub fn init(src: []const u8) Self {
        return Self{ .scanner = Scanner.init(cleanCommand(src)) };
    }

    pub fn next(self: *Self) ParseError!?OptionalToken {
        var s = &self.scanner;
        while (!s.eot()) {
            s.skipSpace();
            if (s.eot()) break;

            const optional = self.opt_depth > 0;
            switch (s.peek()) {
                'A'...'Z', 'a'...'z' => {
                    return wordToken(try s.span(std.ascii.isAlphanumeric), optional);
                },
                '[' => {
                    self.opt_depth += 1;
                    s.advance();
                },
                ']' => {
                    if (self.opt_depth == 0)
                        return ParseError.MissingBracket;
                    self.opt_depth -= 1;
                    s.advance();
                },
                '<' => {
                    s.advance();
                    const name = try s.span(sentinelChecker(':'));
                    if (s.eot()) return ParseError.MissingColon;
                    s.advance();
                    const type_name = try s.span(sentinelChecker('>'));
                    if (s.eot()) return ParseError.BadParameter;
                    s.advance();
                    return parameterToken(name, type_name, optional);
                },
                else => {
                    return literalToken(s.one(), optional);
                },
            }
        }
        if (self.opt_depth > 0)
            return ParseError.MissingBracket;
        return null;
    }
};

const ParamParser = struct {
    const Self = @This();
    iter: Parser,

    pub fn init(source: Source) Self {
        return Self{ .iter = source.iter() };
    }

    pub fn next(self: *Self) ParseError!?OptionalToken {
        while (try self.iter.next()) |token| {
            if (token.token == .Parameter) return token;
        }
        return null;
    }
};

fn iterCount(iter: anytype) !usize {
    var count: usize = 0;
    while (try iter.next()) |_| count += 1;
    return count;
}

fn unpackError(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .error_union => |info| info.payload,
        else => T,
    };
}

fn fieldType(comptime Decoder: type, comptime type_name: []const u8) type {
    const method = @field(Decoder, type_name);
    switch (@typeInfo(@TypeOf(method))) {
        .@"fn" => |f| {
            const rt = f.return_type orelse @compileError("Function must return a type");
            return unpackError(rt);
        },
        else => @compileError("Expected a function type"),
    }
}

fn maybeOptional(comptime T: type, comptime optional: bool) type {
    if (optional)
        return ?T;
    return T;
}

const Source = struct {
    const Self = @This();
    cmd: []const u8,

    pub fn init(cmd: []const u8) Self {
        return Self{ .cmd = cmd };
    }

    pub fn count(self: Self) !usize {
        var it = self.iter();
        return try iterCount(&it);
    }

    pub fn paramCount(self: Self) !usize {
        var it = self.paramIter();
        return try iterCount(&it);
    }

    pub fn iter(self: Self) Parser {
        return Parser.init(self.cmd);
    }

    pub fn paramIter(self: Self) ParamParser {
        return ParamParser.init(self);
    }
};

fn testParser(comptime cmd: []const u8, comptime expect: []const ?OptionalToken) !void {
    const source = Source.init(cmd);
    var iter = source.iter();
    var expect_count: usize = 0;
    inline for (expect) |expected| {
        if (expected) |_|
            expect_count += 1;
        const token = try iter.next();
        try std.testing.expectEqualDeep(expected, token);
    }
    try std.testing.expect(try source.count() == expect_count);
}

test Source {
    try testParser("*FX <A:u8> [,<X:u8> [,<Y:u8>]]", &.{
        wordToken("FX", false),
        parameterToken("A", "u8", false),
        literalToken(",", true),
        parameterToken("X", "u8", true),
        literalToken(",", true),
        parameterToken("Y", "u8", true),
        null,
        null,
    });

    try testParser("FORM40 <drive:u8> [V] [F]", &.{
        wordToken("FORM40", false),
        parameterToken("drive", "u8", false),
        wordToken("V", true),
        wordToken("F", true),
        null,
        null,
    });
}

fn paramType(comptime source: Source, comptime Decoder: type) !type {
    const n_fields = try source.paramCount();
    var names: [n_fields][]const u8 = undefined;
    var types: [n_fields]type = undefined;
    const attrs: [n_fields]std.builtin.Type.StructField.Attributes = @splat(.{});

    var i = source.paramIter();
    var pos: usize = 0;
    while (try i.next()) |token| {
        switch (token.token) {
            .Literal => {},
            .Word => {},
            .Parameter => |param| {
                const pt = maybeOptional(fieldType(Decoder, param.type_name), token.optional);
                names[pos] = param.name;
                types[pos] = pt;
                pos += 1;
            },
        }
    }

    std.debug.assert(pos == n_fields);

    return @Struct(.auto, null, &names, &types, &attrs);
}

fn makeCommand(comptime source: Source) !type {
    comptime {
        @setEvalBranchQuota(40000);
        const PT = try paramType(source, ParamDecoder);
        const token_count = try source.count();
        var tokens: [token_count]OptionalToken = undefined;
        var i = source.iter();
        var index: usize = 0;

        while (try i.next()) |token| : (index += 1)
            tokens[index] = token;

        return struct {
            pub const ParamType = PT;

            pub fn match(cmd: []const u8) !?ParamType {
                var scanner = Scanner.init(cleanCommand(cmd));
                var res = std.mem.zeroInit(ParamType, .{});

                inline for (tokens) |token| {
                    scanner.skipSpace();
                    if (scanner.eot()) {
                        if (!token.optional) return null;
                    } else {
                        const pos = scanner.pos;
                        switch (token.token) {
                            .Literal => |l| {
                                const v = scanner.one();
                                if (!std.mem.eql(u8, v, l.value)) {
                                    if (!token.optional) return null;
                                    scanner.pos = pos;
                                }
                            },
                            .Word => |w| {
                                const v = scanner.takeWhile(std.ascii.isAlphanumeric);
                                // Allow . abbrevation
                                if (!scanner.eot() and scanner.peek() == '.') {
                                    scanner.advance();
                                    if (!std.ascii.startsWithIgnoreCase(w.value[0..v.len], v)) {
                                        if (!token.optional) return null;
                                        scanner.pos = pos;
                                    }
                                } else {
                                    if (!std.ascii.eqlIgnoreCase(w.value, v)) {
                                        if (!token.optional) return null;
                                        scanner.pos = pos;
                                    }
                                }
                            },
                            .Parameter => |param| {
                                const decoder = @field(ParamDecoder, param.type_name);
                                @field(res, param.name) = try decoder(&scanner);
                            },
                        }
                    }
                }

                scanner.skipSpace();
                if (scanner.eot()) return res;

                return null;
            }
        };
    }
}

test makeCommand {
    comptime {
        const source = Source.init(
            \\*FX <A:u8> [,<X:u8> [,<Y:u8>]]
        );
        const command = try makeCommand(source);
        const res1 = try command.match("*FX 1, 2, 3");
        try std.testing.expectEqualDeep(command.ParamType{ .A = 1, .X = 2, .Y = 3 }, res1);
        const res2 = try command.match("fx 1 , 2");
        try std.testing.expectEqualDeep(command.ParamType{ .A = 1, .X = 2, .Y = null }, res2);
        const res3 = try command.match("f x 1 , 2");
        try std.testing.expectEqualDeep(null, res3);
    }
    comptime {
        const source = Source.init(
            \\SAVE <filename:[]u8> <start:u32x> <end:u32x> [<load:u32x> [<exec:u32x>]]
        );
        const command = try makeCommand(source);
        const res1 = try command.match("save foo 800 900");
        try std.testing.expectEqualDeep(command.ParamType{
            .filename = "foo",
            .start = 0x800,
            .end = 0x900,
            .load = null,
            .exec = null,
        }, res1);
        const res2 = try command.match("sa. foo 800 900 a00 b00");
        try std.testing.expectEqualDeep(command.ParamType{
            .filename = "foo",
            .start = 0x800,
            .end = 0x900,
            .load = 0xa00,
            .exec = 0xb00,
        }, res2);
    }
}

pub fn makeHandler(comptime Commands: type) type {
    comptime {
        const info = @typeInfo(Commands);
        switch (info) {
            .@"struct" => |s| {
                var commands: [s.decls.len]type = undefined;
                for (s.decls, 0..) |decl, index| {
                    commands[index] = makeCommand(Source.init(decl.name)) catch |e|
                        @compileError("Failed to parse command: " ++
                            decl.name ++ ": " ++ @errorName(e));
                }

                return struct {
                    pub fn handle(alloc: std.mem.Allocator, cmd: []const u8, cpu: anytype) !bool {
                        inline for (commands, 0..) |command, i| {
                            if (try command.match(cmd)) |params| {
                                const method = @field(Commands, s.decls[i].name);
                                try method(alloc, cpu, params);
                                return true;
                            }
                        }
                        return false;
                    }
                };
            },
            else => {
                @compileError("Expected a struct type for Commands");
            },
        }
    }
}

test makeHandler {
    const allocator = std.testing.allocator;
    const echo = false;
    const Commands = struct {
        pub fn @"*CAT"(alloc: std.mem.Allocator, cpu: anytype, params: anytype) !void {
            _ = alloc;
            _ = cpu;
            _ = params;
            if (echo) std.debug.print("*CAT\n", .{});
        }

        pub fn @"*FX <A:u8> [,<X:u8> [,<Y:u8>]]"(
            alloc: std.mem.Allocator,
            cpu: anytype,
            params: anytype,
        ) !void {
            _ = alloc;
            _ = cpu;
            if (echo) {
                std.debug.print("*FX {d}", .{params.A});
                if (params.X) |x| std.debug.print(", {d}", .{x});
                if (params.Y) |y| std.debug.print(", {d}", .{y});
                std.debug.print("\n", .{});
            }
        }

        pub fn @"*SAVE <name:[]u8> <start:u32x> <end:u32xr> [<exec:u32x>]"(
            alloc: std.mem.Allocator,
            cpu: anytype,
            params: anytype,
        ) !void {
            _ = alloc;
            _ = cpu;
            if (echo) std.debug.print("*SAVE \"{s}\" {x} {x}\n", .{
                params.name,
                params.start,
                params.end.resolve(params.start),
            });
        }

        pub fn @"*!<shell:[]u8*>"(alloc: std.mem.Allocator, cpu: anytype, params: anytype) !void {
            _ = alloc;
            _ = cpu;
            if (echo) std.debug.print("shell {s}\n", .{params.shell});
        }
    };
    const Handler = makeHandler(Commands);

    try std.testing.expect(try Handler.handle(allocator, "*.", null));
    try std.testing.expect(try Handler.handle(allocator, "*FX 1, 2, 3", null));
    try std.testing.expect(try Handler.handle(allocator, "*f.1,2", null));
    try std.testing.expect(try Handler.handle(allocator, "save foo 800 +300", null));
    try std.testing.expect(try Handler.handle(allocator, "sa. \"foo bar\" e00 1234", null));
    try std.testing.expect(try Handler.handle(allocator, "*!ls ..", null));
}

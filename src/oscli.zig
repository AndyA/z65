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

    pub fn span(self: *Self, checker: Checker) ![]const u8 {
        const start = self.pos;
        while (!self.eot() and checker(self.src[self.pos]))
            self.advance();
        if (start == self.pos)
            return ParseError.BadSyntax;
        return self.src[start..self.pos];
    }
};

const ParamDecoder = struct {
    const Self = @This();

    fn notWhitespace(c: u8) bool {
        return !std.ascii.isWhitespace(c);
    }

    pub fn @"[]u8"(src: *Scanner) ![]const u8 {
        return src.span(notWhitespace);
    }

    pub fn @"u8"(src: *Scanner) !u8 {
        const num = try src.span(std.ascii.isDigit);
        return std.fmt.parseInt(u8, num, 10);
    }

    pub fn @"u32"(src: *Scanner) !u32 {
        const num = try src.span(std.ascii.isDigit);
        return std.fmt.parseInt(u32, num, 10);
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
            if (s.eot()) return null;

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

fn structField(comptime name: []const u8, comptime T: type) std.builtin.Type.StructField {
    var z_name: [name.len:0]u8 = @splat(' ');
    @memcpy(&z_name, name);
    return .{
        .name = &z_name,
        .type = T,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = 0,
    };
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
    // try std.testing.expect(try source.count() == expect_count);
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

pub fn paramType(self: Source, comptime Decoder: type) !type {
    const n_fields = try self.paramCount();
    var fields: [n_fields]std.builtin.Type.StructField = undefined;
    var i = self.paramIter();
    var pos: usize = 0;
    while (try i.next()) |token| {
        switch (token.token) {
            .Literal => {},
            .Word => {},
            .Parameter => |param| {
                const pt = maybeOptional(fieldType(Decoder, param.type_name), token.optional);
                fields[pos] = structField(param.name, pt);
                pos += 1;
            },
        }
    }

    std.debug.assert(pos == n_fields);

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

pub fn makeCommand(comptime source: Source) !type {
    comptime {
        @setEvalBranchQuota(4000);
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
                        if (token.optional) continue;
                        return null;
                    }
                    switch (token.token) {
                        .Literal => |l| {
                            const v = scanner.one();
                            if (!std.mem.eql(u8, v, l.value)) {
                                if (token.optional) continue;
                                return null;
                            }
                        },
                        .Word => |w| {
                            const v = try scanner.span(std.ascii.isAlphanumeric);
                            if (!std.ascii.eqlIgnoreCase(w.value, v)) {
                                if (token.optional) continue;
                                return null;
                            }
                        },
                        .Parameter => |param| {
                            const decoder = @field(ParamDecoder, param.type_name);
                            @field(res, param.name) = try decoder(&scanner);
                        },
                    }
                }

                return res;
            }
        };
    }
}

test makeCommand {
    comptime {
        const source = Source.init("*FX <A:u8> [,<X:u8> [,<Y:u8>]]");
        const command = try makeCommand(source);
        const res1 = try command.match("*FX 1, 2, 3");
        try std.testing.expectEqualDeep(command.ParamType{ .A = 1, .X = 2, .Y = 3 }, res1);
        const res2 = try command.match("fx 1 , 2");
        try std.testing.expectEqualDeep(command.ParamType{ .A = 1, .X = 2, .Y = null }, res2);
        const res3 = try command.match("f x 1 , 2");
        try std.testing.expectEqualDeep(null, res3);
    }
}

pub fn makeHandler(comptime Commands: type) type {
    comptime {
        const info = @typeInfo(Commands);
        if (info != .@"struct")
            @compileError("Expected a struct type for Commands");
        return struct {
            const Self = @This();

            pub fn handle(self: Self, cpu: anytype, command: []const u8) !bool {
                _ = self;
                _ = cpu;
                _ = command;
                return false;
            }
        };
    }
}

test "OSCLI" {
    const CoreCommands = struct {
        pub fn @"*FX <A:u8> [,<X:u8> [,<Y:u8>]]"(cpu: anytype, args: anytype) !void {
            std.debug.print("Executing *fx command\n", .{});
            cpu.A = args.A;
            cpu.X = args.X orelse 0;
            cpu.Y = args.Y orelse 0;
        }
    };

    const CoreHandler = makeHandler(CoreCommands);
    _ = CoreHandler;
    const tok = Token{ .Parameter = .{
        .name = "A",
        .type_name = "u8",
    } };
    _ = tok;
}

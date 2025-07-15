const std = @import("std");

const TokenType = enum { Literal, Whitespace, Comma, Parameter };

const Token = union(TokenType) {
    Literal: struct { value: []const u8 },
    Whitespace: struct {},
    Comma: struct {},
    Parameter: struct { name: []const u8, type_name: []const u8 },
};

const OptionalToken = struct {
    token: Token,
    optional: bool,
};

pub fn makeHandler(comptime Commands: type) type {
    _ = Commands;
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

test {
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
    std.debug.print("Hello, Zig!\n", .{});
}

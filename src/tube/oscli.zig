const std = @import("std");
const star = @import("../star_commands.zig");
const constants = @import("constants.zig");

const StarCommands = struct {
    pub fn @"*CAT"(
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = cpu;
        _ = args;
        std.debug.print("Meow!\n", .{});
    }

    pub fn @"LANGUAGE CALLBACK <name:[]u8>"(
        cpu: anytype,
        args: anytype,
    ) !void {
        try cpu.os.lang.onCallback(cpu, args.name);
    }

    pub fn @"*FX <A:u8> [,<X:u8> [,<Y:u8>]]"(
        cpu: anytype,
        args: anytype,
    ) !void {
        cpu.A = args.A;
        cpu.X = args.X orelse 0;
        cpu.Y = args.Y orelse 0;
        cpu.PC = @intFromEnum(constants.MOSEntry.OSBYTE);
    }

    pub fn @"*SAVE <name:[]u8> <start:u16x> <end:u16xr> [<exec:u16x>]"(
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = cpu;
        std.debug.print("*SAVE \"{s}\" {x} {x}\n", .{
            args.name,
            args.start,
            args.end.resolve(args.start),
        });
    }

    pub fn @"*LOAD <name:[]u8> <start:u16x>"(
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = cpu;
        std.debug.print("*LOAD \"{s}\" {x}\n", .{ args.name, args.start });
    }

    pub fn @"*EXEC <name:[]u8>"(
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = cpu;
        std.debug.print("*EXEC \"{s}\"\n", .{args.name});
    }

    pub fn @"*SPOOL <name:[]u8>"(
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = cpu;
        std.debug.print("*SPOOL \"{s}\"\n", .{args.name});
    }

    pub fn @"*!<shell:[]u8*>"(
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = cpu;
        std.debug.print("shell {s}\n", .{args.shell});
    }
};

pub const OSCLI = star.makeHandler(StarCommands);

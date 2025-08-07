const std = @import("std");
const star = @import("../tools/star_commands.zig");
const constants = @import("constants.zig");
const osfile = @import("osfile.zig");

const StarCommands = struct {
    const Self = @This();

    pub fn @"*CAT"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = alloc;
        _ = cpu;
        _ = args;
        std.debug.print("Meow!\n", .{});
    }

    pub fn @"*FX <A:u8> [,<X:u8> [,<Y:u8>]]"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = alloc;
        cpu.A = args.A;
        cpu.X = args.X orelse 0;
        cpu.Y = args.Y orelse 0;
        cpu.PC = @intFromEnum(constants.MOSEntry.OSBYTE);
    }

    pub fn @"*SAVE <name:[]u8> <start:u16x> <end:u16xr> [<exec:u16x>]"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        const cb = osfile.OSFILE_CB{
            .start_addr = args.start,
            .load_addr = args.start,
            .end_addr = args.end.resolve(args.start),
            .exec_addr = args.exec orelse args.start,
        };
        try cb.save(alloc, args.name, cpu);
    }

    pub fn @"*LOAD <name:[]u8> <start:u16x>"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        const cb = osfile.OSFILE_CB{ .load_addr = args.start };
        try cb.load(alloc, args.name, cpu);
    }

    pub fn @"*/ <name:[]u8>"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        try Self.@"*RUN <name:[]u8>"(alloc, cpu, args);
    }

    pub fn @"*RUN <name:[]u8>"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = alloc;
        _ = cpu;
        std.debug.print("*RUN \"{s}\"\n", .{args.name});
    }

    pub fn @"*EXEC <name:[]u8>"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = alloc;
        _ = cpu;
        std.debug.print("*EXEC \"{s}\"\n", .{args.name});
    }

    pub fn @"*SPOOL [<name:[]u8>]"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = alloc;
        _ = cpu;
        if (args.name) |n| {
            std.debug.print("*SPOOL \"{s}\"\n", .{n});
        } else {
            std.debug.print("*SPOOL end\n", .{});
        }
    }

    pub fn @"*QUIT"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = alloc;
        _ = args;
        cpu.stop();
    }

    pub fn @"*DUMP <start:u16x> <end:u16xr> "(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = alloc;
        try cpu.os.hexDump(cpu, args.start, args.end.resolve(args.start));
    }

    pub fn @"*!<shell:[]u8*>"(
        alloc: std.mem.Allocator,
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = alloc;
        _ = cpu;
        std.debug.print("shell {s}\n", .{args.shell});
    }
};

pub const OSCLI = star.makeHandler(StarCommands);

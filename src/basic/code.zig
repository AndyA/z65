const std = @import("std");
const runner = @import("runner.zig");
const constants = @import("../tube/constants.zig");
const util = @import("../tools/util.zig");
const iters = @import("iters.zig");

const HIMEM = @intFromEnum(constants.Symbols.HIMEM);
const PAGE = @intFromEnum(constants.Symbols.PAGE);
const ZP_TOP = 0x12;

pub const CodeError = error{ProgramTooLarge};

pub fn validBinary(prog: []const u8) iters.BasicIterError![]const u8 {
    var i = iters.BasicIter.init(prog);
    var last_line: u16 = 0;
    while (try i.next()) |line| {
        if (last_line != 0 and line.line_number <= last_line)
            return iters.BasicIterError.BadProgram;
        last_line = line.line_number;
    }
    return prog;
}

pub fn getProgram(ram: *[0x10000]u8) ![]const u8 {
    const top = util.peek16(ram, ZP_TOP);
    return validBinary(ram[PAGE..top]);
}

pub fn setProgram(ram: *[0x10000]u8, prog: []const u8) !void {
    if (prog.len > HIMEM - PAGE - 0x100)
        return CodeError.ProgramTooLarge;
    @memcpy(ram[PAGE .. PAGE + prog.len], try validBinary(prog));
}

pub const Code = struct {
    const Self = @This();
    alloc: std.mem.Allocator,
    bytes: []const u8,
    hash: u256,

    pub fn init(alloc: std.mem.Allocator, bytes: []const u8) !Self {
        const bytes_copy = try alloc.dupe(u8, bytes);
        return Self{
            .alloc = alloc,
            .bytes = bytes_copy,
            .hash = util.hashBytes(bytes_copy),
        };
    }

    pub fn deinit(self: Self) void {
        self.alloc.free(self.bytes);
    }
};

pub fn sourceToBinary(alloc: std.mem.Allocator, prog: []const u8) !Code {
    var r = std.io.Reader.fixed(prog);
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(alloc, &buf);
    defer w.deinit();

    var ram: [0x10000]u8 = @splat(0);
    try runner.runHiBasic(alloc, &ram, &r, &w.writer);

    return try Code.init(alloc, try getProgram(&ram));
}

pub fn sourceCodeToBinary(source: Code) !Code {
    return try sourceToBinary(source.alloc, source.bytes);
}

test sourceCodeToBinary {
    const allocator = std.testing.allocator;

    const prog =
        \\   10 PRINT "Hello, World"
        \\   20 GOTO 10
        \\
    ;

    const source = try Code.init(allocator, prog);
    defer source.deinit();

    const bin = try sourceCodeToBinary(source);
    defer bin.deinit();

    // hexDump(bin.bytes);

    _ = try validBinary(bin.bytes);
}

pub fn binaryToSource(alloc: std.mem.Allocator, prog: []const u8) !Code {
    var r = std.io.Reader.fixed(
        \\OLD
        \\LIST
    );
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(alloc, &buf);
    defer w.deinit();

    var ram: [0x10000]u8 = @splat(0);
    try setProgram(&ram, prog);
    try runner.runHiBasic(alloc, &ram, &r, &w.writer);

    var output = w.toArrayList();
    defer output.deinit(alloc);
    runner.cleanBasicOutput(&output);

    return try Code.init(alloc, output.items);
}

pub fn binaryCodeToSource(binary: Code) !Code {
    return try binaryToSource(binary.alloc, binary.bytes);
}

test binaryCodeToSource {
    const allocator = std.testing.allocator;

    const prog =
        \\   10 PRINT "Hello, World"
        \\   20 GOTO 10
        \\
    ;

    const in_source = try Code.init(allocator, prog);
    defer in_source.deinit();

    const bin = try sourceCodeToBinary(in_source);
    defer bin.deinit();

    // hexDump(bin.bytes);

    const out_source = try binaryCodeToSource(bin);
    defer out_source.deinit();

    // std.debug.print("{s}", .{out_source.bytes});

    try std.testing.expectEqualDeep(prog, out_source.bytes);
}

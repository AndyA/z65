const std = @import("std");
const runner = @import("runner.zig");
const constants = @import("constants.zig");
const util = @import("../tools/util.zig");
const iters = @import("iters.zig");

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
    const top = util.peek16(ram, constants.ZP.TOP);
    return validBinary(ram[constants.PAGE..top]);
}

pub fn setProgram(ram: *[0x10000]u8, prog: []const u8) !void {
    if (prog.len > constants.HIMEM - constants.PAGE - 0x100)
        return CodeError.ProgramTooLarge;
    @memcpy(ram[constants.PAGE .. constants.PAGE + prog.len], try validBinary(prog));
}

pub fn clearVariables(ram: *[0x10000]u8) void {
    const ZP = constants.ZP;
    // f523   a5 12      lf523     lda $12       ; top
    // f525   85 00                sta $00
    // f527   85 02                sta $02
    // f529   a5 13                lda $13
    // f52b   85 01                sta $01
    // f52d   85 03                sta $03
    const top = util.peek16(ram, ZP.TOP);
    util.poke16(ram, ZP.VARTOP, top);
    util.poke16(ram, 0x02, top);
    // f53d   a5 18      lf53d     lda $18
    // f53f   85 1d                sta $1d
    ram[0x1d] = ram[ZP.PAGE_HI];
    // f541   a5 06                lda $06
    // f543   85 04                sta $04
    // f545   a5 07                lda $07
    // f547   85 05                sta $05
    util.poke16(ram, ZP.SP, util.peek16(ram, ZP.HIMEM));
    // f549   a9 00                lda #$00
    // f54b   85 24                sta $24
    // f54d   85 26                sta $26
    // f54f   85 25                sta $25
    // f551   85 1c                sta $1c
    ram[0x1c] = 0x00;
    ram[0x24] = 0x00;
    ram[0x25] = 0x00;
    ram[0x26] = 0x00;
    // f532   a2 80      lf532     ldx #$80
    // f534   a9 00                lda #$00
    // f536   9d 7f 04   lf536     sta $047f,x
    // f539   ca                   dex
    // f53a   d0 fa                bne lf536
    const vars = constants.VAR_CHAINS;
    @memset(ram[vars .. vars + 0x80], 0x00);
}

pub fn sourceToBinary(alloc: std.mem.Allocator, prog: []const u8) ![]const u8 {
    var r = std.io.Reader.fixed(prog);
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(alloc, &buf);
    defer w.deinit();

    var ram: [0x10000]u8 = @splat(0);
    try runner.runHiBasic(alloc, &ram, &r, &w.writer);

    return try alloc.dupe(u8, try getProgram(&ram));
}

test sourceToBinary {
    const alloc = std.testing.allocator;

    const prog =
        \\   10 PRINT "Hello, World"
        \\   20 GOTO 10
        \\
    ;

    const bin = try sourceToBinary(alloc, prog);
    defer alloc.free(bin);

    _ = try validBinary(bin);
}

pub fn binaryToSource(alloc: std.mem.Allocator, prog: []const u8) ![]const u8 {
    if (prog.len == 2) return alloc.dupe(u8, "");
    var r = std.io.Reader.fixed(
        \\OLD
        \\LIST
    );
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(alloc, &buf);
    defer w.deinit();

    var ram: [0x10000]u8 = @splat(0);
    try setProgram(&ram, prog);
    // Why doesn't this fail on Bad Program?
    try runner.runHiBasic(alloc, &ram, &r, &w.writer);

    var output = w.toArrayList();
    defer output.deinit(alloc);
    runner.cleanBasicOutput(&output);

    return try alloc.dupe(u8, output.items);
}

test binaryToSource {
    const alloc = std.testing.allocator;

    const prog =
        \\   10 PRINT "Hello, World"
        \\   20 GOTO 10
        \\
    ;

    const bin = try sourceToBinary(alloc, prog);
    defer alloc.free(bin);

    const out_source = try binaryToSource(alloc, bin);
    defer alloc.free(out_source);

    try std.testing.expectEqualDeep(prog, out_source);
}

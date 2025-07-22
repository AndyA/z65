const std = @import("std");
const kw = @import("keywords.zig");
const code = @import("code.zig");
const iters = @import("iters.zig");
const util = @import("../tools/util.zig");

pub const ConverterError = error{MixedLineNumbers};

pub fn needsLineNumbers(prog: []const u8) !bool {
    var ti = iters.TokenIter.init(prog);
    while (try ti.next()) |tok| {
        if (kw.isGotoLike(tok)) return true;
    }
    return false;
}

test needsLineNumbers {
    const alloc = std.testing.allocator;

    {
        const bin = try code.sourceToBinary(alloc,
            \\   10 PRINT """Hello, World""" : REM Quotes!
            \\   20 DATA Hello, World
            \\   30 RESTORE 20
            \\
        );
        defer alloc.free(bin);
        try std.testing.expect(try needsLineNumbers(bin));
    }

    {
        const bin = try code.sourceToBinary(alloc,
            \\   10 PRINT """Hello, World""" : REM Quotes!
            \\   20 DATA Hello, World
            \\
        );
        defer alloc.free(bin);
        try std.testing.expect(!try needsLineNumbers(bin));
    }
}

pub const SourceInfo = struct { line_numbers: bool, indent: usize };

pub fn getSourceInfo(source: []const u8) !SourceInfo {
    var iter = std.mem.splitScalar(u8, source, '\n');
    var line_numbers: ?bool = null;
    var min_indent: usize = std.math.maxInt(usize);
    while (iter.next()) |line| {
        var pos: usize = 0;
        while (pos < line.len and std.ascii.isWhitespace(line[pos])) pos += 1;
        if (pos >= line.len) continue;
        if (pos < line.len and std.ascii.isDigit(line[pos])) {
            if (line_numbers) |ln| {
                if (!ln) return ConverterError.MixedLineNumbers;
            }
            line_numbers = true;
            while (pos < line.len and std.ascii.isDigit(line[pos])) pos += 1;
            const start = pos;
            while (pos < line.len and std.ascii.isWhitespace(line[pos])) pos += 1;
            min_indent = @min(min_indent, pos - start);
        } else {
            if (line_numbers) |ln| {
                if (ln) return ConverterError.MixedLineNumbers;
            }
            line_numbers = false;
            min_indent = @min(min_indent, pos);
        }
    }
    if (line_numbers) |ln| return SourceInfo{
        .indent = min_indent,
        .line_numbers = ln,
    };
    return SourceInfo{
        .indent = 0,
        .line_numbers = false,
    };
}

test getSourceInfo {
    try std.testing.expectEqual(
        SourceInfo{ .indent = 0, .line_numbers = false },
        try getSourceInfo(""),
    );
    try std.testing.expectEqual(
        SourceInfo{ .indent = 2, .line_numbers = true },
        try getSourceInfo(
            \\   10  PRINT "Hello"
        ),
    );
    try std.testing.expectEqual(
        SourceInfo{ .indent = 2, .line_numbers = true },
        try getSourceInfo(
            \\   10  PRINT "Hello"
            \\20  GOTO 10
        ),
    );
    try std.testing.expectEqual(
        SourceInfo{ .indent = 2, .line_numbers = false },
        try getSourceInfo(
            \\  REPEAT
            \\    PRINT "Hello"
            \\  UNTIL FALSE
            \\
        ),
    );
}

fn withoutLastLine(text: []const u8) []const u8 {
    var pos = text.len;
    if (pos > 0 and text[pos - 1] == '\n') pos -= 1;
    return text[0..pos];
}

pub fn parseSource(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    const info = try getSourceInfo(source);
    if (info.line_numbers)
        return try code.sourceToBinary(alloc, source);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(alloc, &buf);
    defer w.deinit();

    const src = withoutLastLine(source);
    if (src.len > 0) {
        var iter = std.mem.splitScalar(u8, src, '\n');
        var num: usize = 10;
        while (iter.next()) |line| : (num += 10) {
            const tail = line[@min(line.len, info.indent)..];
            try w.writer.print("{d} {s}\n", .{ num, tail });
        }
    }
    var output = w.toArrayList();
    defer output.deinit(alloc);

    return try code.sourceToBinary(alloc, output.items);
}

pub fn stringifyBinary(alloc: std.mem.Allocator, bin: []const u8) ![]const u8 {
    const needs_numbers = try needsLineNumbers(bin);
    const source = try code.binaryToSource(alloc, bin);
    if (needs_numbers)
        return source;
    defer alloc.free(source);

    const info = try getSourceInfo(source);
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(alloc, &buf);
    defer w.deinit();

    var iter = std.mem.splitScalar(u8, withoutLastLine(source), '\n');
    while (iter.next()) |line| {
        var pos: usize = 0;
        while (pos < line.len and std.ascii.isWhitespace(line[pos]))
            pos += 1;
        while (pos < line.len and std.ascii.isDigit(line[pos]))
            pos += 1;
        const tail = line[@min(line.len, pos + info.indent)..];
        try w.writer.print("{s}\n", .{tail});
    }

    var output = w.toArrayList();
    defer output.deinit(alloc);
    return try alloc.dupe(u8, output.items);
}

pub fn roundTrip(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    const bin = try parseSource(alloc, source);
    defer alloc.free(bin);
    return try stringifyBinary(alloc, bin);
}

test roundTrip {
    const alloc = std.testing.allocator;

    {
        const out = try roundTrip(alloc,
            \\ 10 PRINT "Hello"
            \\
        );
        const want =
            \\PRINT "Hello"
            \\
        ;
        defer alloc.free(out);
        try std.testing.expect(std.mem.eql(u8, want, out));
    }

    {
        const out = try roundTrip(alloc,
            \\     REPEAT
            \\        PRINT "Hello"
            \\     UNTIL FALSE
            \\
        );
        const want =
            \\REPEAT
            \\   PRINT "Hello"
            \\UNTIL FALSE
            \\
        ;
        defer alloc.free(out);
        try std.testing.expect(std.mem.eql(u8, want, out));
    }

    {
        const out = try roundTrip(alloc,
            \\ 10 PRINT "Hello"
            \\ 20 GOTO 10
            \\
        );
        const want =
            \\   10 PRINT "Hello"
            \\   20 GOTO 10
            \\
        ;
        defer alloc.free(out);
        try std.testing.expect(std.mem.eql(u8, want, out));
    }

    {
        const out = try roundTrip(alloc,
            \\PRINT "Hello"
            \\GOTO 10
            \\
        );
        const want =
            \\   10 PRINT "Hello"
            \\   20 GOTO 10
            \\
        ;
        defer alloc.free(out);
        try std.testing.expect(std.mem.eql(u8, want, out));
    }
}

const std = @import("std");

fn skipLineNumber(line: []const u8) []const u8 {
    var i: usize = 0;
    while (i < line.len and std.ascii.isWhitespace(line[i])) : (i += 1) {}
    while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) {}
    return line[i..];
}

fn leadingSpace(line: []const u8) usize {
    var i: usize = 0;
    while (i < line.len and std.ascii.isWhitespace(line[i])) : (i += 1) {}
    return i;
}

const LineIter = struct {
    const Self = @This();
    source: []const u8,
    iter: std.mem.SplitIterator(u8, .scalar),
    strip_line_numbers: bool = true,
    strip_space: usize,

    pub fn init(source: []const u8, strip_line_number: bool, strip_space: usize) Self {
        return Self{
            .source = source,
            .iter = std.mem.splitScalar(u8, source, '\n'),
            .strip_line_numbers = strip_line_number,
            .strip_space = strip_space,
        };
    }

    fn strip(self: Self, line: []const u8) []const u8 {
        return switch (self.strip_line_numbers) {
            true => skipLineNumber(line),
            false => line,
        };
    }

    pub fn next(self: *Self) ?[]const u8 {
        while (self.iter.next()) |line| {
            const clean = self.strip(std.mem.trim(u8, line, "\r"));
            if (self.iter.peek() == null and clean.len == 0)
                break;
            return clean[@min(self.strip_space, clean.len)..];
        }
        return null;
    }
};

test LineIter {
    var line_iter = LineIter.init("10 PRINT \"HELLO\"\n\r20 END\n\r", false, 0);

    try std.testing.expectEqualDeep("10 PRINT \"HELLO\"", line_iter.next());
    try std.testing.expectEqualDeep("20 END", line_iter.next());
    // try std.testing.expectEqualDeep(null, line_iter.next());
}

pub const BBCBasicWriter = struct {
    const Self = @This();
    source: []const u8,
    strip: bool = false,

    pub fn uncookedIter(self: Self) LineIter {
        return LineIter.init(self.source, false, 0);
    }

    pub fn iter(self: Self) LineIter {
        if (self.strip) {
            const ls = self.findLeadingSpace();
            return LineIter.init(self.source, true, ls);
        } else {
            return self.uncookedIter();
        }
    }

    fn findLeadingSpace(self: Self) usize {
        var i = self.uncookedIter();
        var ls: usize = 256;
        while (i.next()) |line| {
            const clean = skipLineNumber(line);
            const spc = leadingSpace(clean);
            if (spc == clean.len) continue; // empty line
            ls = @min(ls, spc);
        }
        return ls;
    }
};

pub const BBCBasicReader = struct {
    const Self = @This();
    source: []const u8,
    alloc: std.mem.Allocator,
    buf: std.ArrayList(u8),

    pub fn init(source: []const u8, alloc: std.mem.Allocator) !Self {
        return Self{
            .source = source,
            .alloc = alloc,
            .buf = try std.ArrayList(u8).initCapacity(alloc, source.len * 2),
        };
    }

    pub fn deinit(self: Self) void {
        self.buf.deinit();
    }

    pub fn uncookedIter(self: Self) LineIter {
        return LineIter.init(self.source, false, 0);
    }

    fn hasLineNumbers(self: Self) bool {
        var i = self.uncookedIter();
        while (i.next()) |line| {
            const ls = leadingSpace(line);
            if (ls == line.len) continue;
            if (!std.ascii.isDigit(line[ls]))
                return false;
        }
        return true;
    }

    fn write(self: Self, w: std.ArrayList(u8).Writer) !void {
        var i = self.uncookedIter();
        if (self.hasLineNumbers()) {
            while (i.next()) |line| {
                try w.print("{s}\n", .{line});
            }
        } else {
            var ln: usize = 10;
            while (i.next()) |line| : (ln += 10) {
                try w.print("{d} {s}\n", .{ ln, line });
            }
        }
    }

    fn render(self: *Self) !void {
        if (self.buf.items.len == 0) {
            try self.write(self.buf.writer());
        }
    }

    pub fn iter(self: *Self) !LineIter {
        try self.render();
        return LineIter.init(self.buf.items, false, 0);
    }
};

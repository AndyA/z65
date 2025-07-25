const std = @import("std");

pub const WrapIter = struct {
    const Self = @This();
    text: []const u8,
    max_width: usize,
    pos: usize = 0,

    pub fn init(text: []const u8, max_width: usize) Self {
        return Self{ .text = text, .max_width = max_width };
    }

    pub fn next(self: *Self) ?[]const u8 {
        var np = self.pos;
        var break_start: usize = 0;
        var break_end: usize = 0;

        if (self.pos == self.text.len)
            return null;

        while (np < self.text.len) : (np += 1) {
            const c = self.text[np];
            if (c == '\n') break;
            if (std.ascii.isWhitespace(c)) {
                const in_bounds = np - self.pos <= self.max_width;
                if (in_bounds)
                    break_start = np;
                while (np < self.text.len and std.ascii.isWhitespace(self.text[np])) : (np += 1) {
                    if (self.text[np] == '\n') break;
                }
                if (!in_bounds) break;
                break_end = np;
            }
        }

        if (np - self.pos <= self.max_width or break_start == 0) {
            var ep = np;
            while (ep > 0 and std.ascii.isWhitespace(self.text[ep - 1])) ep -= 1;
            const line = self.text[self.pos..ep];
            self.pos = np;
            if (self.pos < self.text.len and self.text[self.pos] == '\n')
                self.pos += 1;
            while (np > 0 and std.ascii.isWhitespace(self.text[np - 1])) np -= 1;

            return line;
        } else {
            const line = self.text[self.pos..break_start];
            if (break_end == 0) {}
            self.pos = break_end;

            return line;
        }
    }
};

test WrapIter {
    {
        var i = WrapIter.init("", 75);
        try std.testing.expectEqualDeep(null, i.next());
    }
    {
        var i = WrapIter.init(
            \\one two three four five six seven
            \\eight nine ten
        ,
            20,
        );
        try std.testing.expectEqualDeep("one two three four", i.next());
        try std.testing.expectEqualDeep("five six seven", i.next());
        try std.testing.expectEqualDeep("eight nine ten", i.next());
        try std.testing.expectEqualDeep(null, i.next());
    }
    {
        var i = WrapIter.init(
            \\one two three four five six seven eight nine ten
        ,
            20,
        );
        try std.testing.expectEqualDeep("one two three four", i.next());
        try std.testing.expectEqualDeep("five six seven eight", i.next());
        try std.testing.expectEqualDeep("nine ten", i.next());
        try std.testing.expectEqualDeep(null, i.next());
    }
    {
        var i = WrapIter.init(
            \\one two aVeryLongWordThatWontSplit four five six seven
        ,
            10,
        );
        try std.testing.expectEqualDeep("one two", i.next());
        try std.testing.expectEqualDeep("aVeryLongWordThatWontSplit", i.next());
        try std.testing.expectEqualDeep("four five", i.next());
        try std.testing.expectEqualDeep("six seven", i.next());
        try std.testing.expectEqualDeep(null, i.next());
    }
}

const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const u = std.unicode;

const builtin = @import("builtin");

const ansi = @import("ansi.zig");
const tools = @import("unicode/tools.zig");

pub const Term = switch (builtin.os.tag) {
    .windows => @compileError("Sorry - no Windows support yet"),
    else => @import("platform/posix.zig"),
};

fn utf8Valid(chars: []const u8) bool {
    var pos: usize = 0;
    while (pos < chars.len)
        pos += u.utf8ByteSequenceLength(chars[pos]) catch return false;
    return pos == chars.len;
}

const Editor = struct {
    const Self = @This();

    pub const Char = packed struct {
        pos: u16,
        len: u14,
        width: u2, // display width
    };

    buffer: []u8,
    buf_used: u16 = 0,

    chars: []Char,
    char_pos: u16 = 0,
    char_used: u16 = 0,

    pub fn init(buffer: []u8, chars: []Char) Self {
        assert(buffer.len == chars.len);
        return .{ .buffer = buffer, .chars = chars };
    }

    fn charStartIndex(self: Self, char_pos: u16) u16 {
        assert(char_pos <= self.char_used);
        if (char_pos == self.char_used)
            return self.buf_used;
        return self.chars[char_pos].pos;
    }

    fn charEndIndex(self: Self, char_pos: u16) u16 {
        assert(char_pos < self.char_used);
        return self.charStartIndex(char_pos) + self.chars[char_pos].len;
    }

    fn endOfCharsIndex(self: Self) u16 {
        if (self.char_used == 0) return 0;
        return self.charEndIndex(self.char_used - 1);
    }

    fn recalcChars(self: *Self) void {
        const buf = self.buffer;
        var pos = self.endOfCharsIndex();

        while (pos < self.buf_used) {
            const bytes = u.utf8ByteSequenceLength(buf[pos]) catch unreachable;
            const cp = u.utf8Decode(buf[pos .. pos + bytes]) catch unreachable;
            const width = tools.countCells(cp);
            if (width == 0 and self.char_used != 0) { // zero width
                // Extend previous char's span
                self.chars[self.char_used - 1].len += bytes;
            } else {
                assert(self.char_used <= self.chars.len);
                defer self.char_used += 1;
                self.chars[self.char_used] = .{
                    .pos = pos,
                    .len = bytes,
                    .width = width,
                };
            }
            pos += bytes;
        }
    }

    fn recalcForward(self: *Self) void {
        self.char_used = self.char_pos;
        self.recalcChars();
    }

    fn assertHealthy(self: Self) void {
        assert(self.endOfCharsIndex() == self.buf_used);
        assert(self.char_pos <= self.char_used);
    }

    pub fn moveLeft(self: *Self) bool {
        self.assertHealthy();
        if (self.char_pos == 0) return false;
        self.char_pos -= 1;
        return true;
    }

    pub fn moveRight(self: *Self) bool {
        self.assertHealthy();
        assert(self.char_pos <= self.char_used);
        if (self.char_pos == self.char_used) return false;
        self.char_pos += 1;
        return true;
    }

    pub fn goStart(self: *Self) void {
        self.assertHealthy();
        self.char_pos = 0;
    }

    pub fn goEnd(self: *Self) void {
        self.assertHealthy();
        self.char_pos = self.char_used;
    }

    pub fn insert(self: *Self, bytes: []const u8) bool {
        self.assertHealthy();
        assert(utf8Valid(bytes));

        if (self.buf_used + bytes.len >= self.buffer.len)
            return false;

        const idx = self.charStartIndex(self.char_pos);

        // Shift buffer to make space
        @memmove(
            self.buffer[idx + bytes.len .. self.buf_used + bytes.len],
            self.buffer[idx..self.buf_used],
        );
        self.buf_used += @as(u16, @intCast(bytes.len));

        // Copy char
        @memcpy(self.buffer[idx .. idx + bytes.len], bytes);

        // Rebuild self.chars
        const before = self.char_used;
        self.recalcForward();
        self.char_pos += self.char_used - before;
        return true;
    }

    pub fn deleteRight(self: *Self) bool {
        self.assertHealthy();
        if (self.char_pos == self.char_used)
            return false;
        const idx = self.charStartIndex(self.char_pos);
        const len = self.chars[self.char_pos].len;
        @memmove(
            self.buffer[idx .. self.buf_used - len],
            self.buffer[idx + len .. self.buf_used],
        );
        self.buf_used -= len;
        self.recalcForward();
        return true;
    }

    pub fn deleteLeft(self: *Self) bool {
        return self.moveLeft() and self.deleteRight();
    }

    pub fn killAll(self: *Self) void {
        self.assertHealthy();
        self.buf_used = 0;
        self.char_used = 0;
        self.char_pos = 0;
    }

    pub fn killLeft(self: *Self) void {
        self.assertHealthy();
        const idx = self.charStartIndex(self.char_pos);
        const len = self.buf_used - idx;
        @memmove(self.buffer[0..len], self.buffer[idx..self.buf_used]);
        self.buf_used = len;
        self.char_pos = 0;
        self.recalcForward();
    }

    pub fn killRight(self: *Self) void {
        self.assertHealthy();
        self.buf_used = self.charStartIndex(self.char_pos);
        self.char_used = self.char_pos;
    }

    pub fn getChars(self: Self) []const Char {
        self.assertHealthy();
        return self.chars[0..self.char_used];
    }

    pub fn getBytes(self: Self) []const u8 {
        self.assertHealthy();
        return self.buffer[0..self.buf_used];
    }
};

const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;

test Editor {
    var buf: [256]u8 = undefined;
    var chars: [256]Editor.Char = undefined;

    var editor: Editor = .init(&buf, &chars);
    try expectEqual(true, editor.insert("a"));
    try expectEqual(true, editor.insert("ᄀ"));
    try expectEqual(true, editor.moveLeft());
    try expectEqual(true, editor.insert("e"));

    for (editor.getChars()) |c| {
        print("{}\n", .{c});
    }

    try expectEqual(true, editor.insert("\xcc\x80"));

    for (editor.getChars()) |c| {
        print("{}\n", .{c});
    }
}

pub const Linen = struct {
    const Self = @This();

    engine: *ansi.Engine,

    pub fn readLine(self: *Self, buffer: []u8) error{Escape}![]const u8 {
        // var pos:usize = 0;

        var editor: Editor = .init(buffer);

        while (true) {
            switch (self.engine.poll(null)) {
                .char => {},
                .meta => |m| switch (m) {
                    .LEFT => _ = editor.moveLeft(),
                    .RIGHT => _ = editor.moveRight(),
                },
                .escape => return error{Escape},
                .timeout => unreachable,
            }
        }

        return buffer;
    }
};

const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

const builtin = @import("builtin");

const ansi = @import("ansi.zig");
const tools = @import("unicode/tools.zig");

pub const Term = switch (builtin.os.tag) {
    .windows => @compileError("Sorry - no Windows support yet"),
    else => @import("platform/posix.zig"),
};

fn utf8Valid(chars: []u8) bool {
    var pos = 0;
    while (pos < chars.len)
        pos += std.unicode.utf8ByteSequenceLength(chars[pos]);
    return pos == chars.len;
}

const Editor = struct {
    const Self = @This();

    pub const Char = struct {
        bytes: []u8,
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

    fn charStartIndex(self: Self, char: Char) u16 {
        return @intCast(@intFromPtr(char.bytes.ptr) - @intFromPtr(self.buffer.ptr));
    }

    fn refreshChars(self: *Self) void {
        var buf_pos = if (self.char_used > 0) self.chars[self.char_used - 1] else 0;
        while (buf_pos < self.buf_used) {
            const bytes = std.unicode.utf8ByteSequenceLength(self.buffer[buf_pos]) catch unreachable;
            const codepoint = std.unicode.utf8Decode(self.buffer[buf_pos .. buf_pos + bytes]);
            const cells = tools.countCells(codepoint);
            if (cells == 0) { // zero width
                if (self.char_used == 0) {
                    assert(self.char_used <= self.chars.len);
                    self.chars[self.char_used] = .{
                        .bytes = self.buffer[buf_pos .. buf_pos + bytes],
                        .width = 0,
                    };
                    self.char_used += 1;
                } else {
                    // Extend char's span
                    self.chars[self.char_used - 1].bytes.len += bytes;
                }
            } else {
                assert(self.char_used <= self.chars.len);
                self.chars[self.char_used] = .{
                    .bytes = self.buffer[buf_pos .. buf_pos + bytes],
                    .width = cells,
                };
                self.char_used += 1;
            }
            buf_pos += bytes;
        }
    }

    fn refreshForward(self: *Self) void {
        self.char_used = self.char_pos;
        self.refreshChars();
    }

    fn assertHealthy(self: *Self) void {
        const buf_pos = if (self.char_used > 0) self.chars[self.char_used - 1] else 0;
        assert(buf_pos == self.buf_used);
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

    pub fn insert(self: *Self, char: []const u8) bool {
        self.assertHealthy();
        assert(char.len != 0);
        assert(utf8Valid(char));

        if (self.buf_used + char.len >= self.buffer.len)
            return false;
        const idx = if (self.char_pos == self.char_used)
            self.buf_used
        else
            self.charStartIndex(self.chars[self.char_pos]);

        // Shift buffer to make space
        @memmove(
            self.buffer[idx..self.buf_used],
            self.buffer[idx + char.len .. self.buf_used + char.len],
        );
        self.buf_used += char.len;
        // Copy char
        @memcpy(self.buffer[idx .. idx + char.len], char);

        // Rebuild self.chars
        const before = self.char_used;
        self.refreshForward();
        self.char_pos += self.char_used - before;
        return true;
    }

    pub fn deleteRight(self: *Self) bool {
        self.assertHealthy();
        if (self.char_pos == self.char_used)
            return false;
        const idx = self.charStartIndex(self.chars[self.char_pos]);
        const len = self.chars[self.char_pos].bytes.len;
        @memmove(
            self.buffer[idx .. self.buf_used - len],
            self.buffer[idx + len .. self.buf_used],
        );
        self.buf_used -= len;
        self.refreshForward();
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
        if (self.char_pos == self.char_used)
            return self.killAll();
        const idx = self.charStartIndex(self.chars[self.char_pos]);
        const len = self.buf_used - idx;
        @memmove(self.buffer[0..len], self.buffer[idx..self.buf_used]);
        self.buf_used = len;
        self.char_pos = 0;
        self.refreshForward();
    }

    pub fn killRight(self: *Self) void {
        self.assertHealthy();
        if (self.char_pos == 0)
            return self.killAll()
        else if (self.char_pos == self.char_used)
            return;
        self.buf_used = self.charStartIndex(self.chars[self.char_pos]);
        self.char_used = self.char_pos;
    }
};

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

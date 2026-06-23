const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

const builtin = @import("builtin");

const ansi = @import("ansi.zig");

pub const Term = switch (builtin.os.tag) {
    .windows => @compileError("Sorry - no Windows support yet"),
    else => @import("platform/posix.zig"),
};

const Editor = struct {
    const Self = @This();

    buffer: []u8,
    pos: u16 = 0,
    used: u16 = 0,

    pub fn init(buffer: []u8) Self {
        return .{ .buffer = buffer };
    }

    pub fn moveLeft(self: *Self) bool {
        assert(self.pos <= self.used);
        assert(self.used <= self.buffer.len);
        if (self.pos == 0) return false;
        self.pos -= 1;
        return true;
    }

    pub fn moveRight(self: *Self) bool {
        assert(self.pos <= self.used);
        assert(self.used <= self.buffer.len);
        if (self.pos == self.used) return false;
        self.pos += 1;
        return true;
    }

    pub fn insert(self: *Self, chars: []const u8) bool {
        assert(self.pos <= self.used);
        assert(self.used <= self.buffer.len);
        if (chars.len + self.used > self.buffer.len)
            return false;
        @memmove(
            self.buffer[self.pos + chars.len .. self.used + chars.len],
            self.buffer[self.pos..self.used],
        );
        @memcpy(self.buffer[self.pos .. self.pos + chars.len], chars);
        self.pos += chars.len;
        self.used += chars.len;
        assert(self.pos <= self.used);
        assert(self.used <= self.buffer.len);
        return true;
    }

    pub fn deleteRight(self: *Self) bool {
        assert(self.pos <= self.used);
        assert(self.used <= self.buffer.len);
        if (self.pos == self.used)
            return false;
        @memmove(
            self.buffer[self.pos .. self.used - 1],
            self.buffer[self.pos + 1 .. self.used],
        );
        self.used -= 1;
        assert(self.pos <= self.used);
        assert(self.used <= self.buffer.len);
    }

    pub fn deleteLeft(self: *Self) bool {
        return self.moveLeft() and self.deleteRight();
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

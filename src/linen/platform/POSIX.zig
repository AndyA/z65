const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const builtin = @import("builtin");

const string = @cImport(@cInclude("string.h"));

const Self = @This();
pub const Error = std.posix.TermiosGetError || std.posix.TermiosSetError;

pub const Config = struct {
    stdin: Io.File,
};

config: Config,
previous_termios: std.posix.termios = undefined,

pub fn init(config: Config) Error!Self {
    const previous_termios: std.posix.termios = try std.posix.tcgetattr(config.stdin.handle);

    var termios = previous_termios;

    termios.iflag.IGNBRK = true;
    termios.iflag.INLCR = false;
    termios.lflag.ICANON = false;
    termios.lflag.ECHO = false;

    const flags = [_][]const u8{ "INTR", "DSUSP", "SUSP", "START", "STOP" };

    inline for (flags) |flag| {
        if (@hasField(std.posix.V, flag))
            termios.cc[@intFromEnum(@field(std.posix.V, flag))] = 0xff;
    }

    try std.posix.tcsetattr(config.stdin.handle, std.posix.TCSA.NOW, termios);

    return Self{ .config = config, .previous_termios = previous_termios };
}

pub fn deinit(self: Self) void {
    std.posix.tcsetattr(self.config.stdin.handle, std.posix.TCSA.NOW, self.previous_termios) catch {
        const errno_val = std.c._errno().*;
        const errno_string = string.strerror(errno_val);

        std.log.err("{s}\n", .{errno_string});
    };
}

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
    termios.lflag.ICANON = false;
    termios.lflag.ECHO = false;

    termios.cc[@intFromEnum(std.posix.V.INTR)] = 0xff; // disable
    if (@hasDecl(std.posix.V, "DSUSP"))
        termios.cc[@intFromEnum(std.posix.V.DSUSP)] = 0xff; // disable
    if (@hasDecl(std.posix.V, "SUSP"))
        termios.cc[@intFromEnum(std.posix.V.SUSP)] = 0xff; // disable

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

// * send the query
// * advance the state machine until
//   - either the cursor position has been reported
//   - or we timeout (~20ms)

const CSI = "\x1B[";
pub fn getCursorPosition(self: Self, input: anytype) !void {
    _ = self;
    try input.writeAll(CSI ++ "6n");

    // const State = enum(u8) { BYTE0, BYTE1, VPOS };
    // var state: State = .BYTE0;
    // var vpos: i32 = 0;
    // while (true) {
    //     const bytes = try input.readInput();
    //     for (bytes) |b| {
    //         switch (state) {
    //             .BYTE0 => {
    //                 if (b == 0x1b) state = .BYTE1 else return error.BadResponse;
    //             },
    //             .BYTE1 => {
    //                 if (b == '[') state = .VPOS else return error.BadResponse;
    //             },
    //             .VPOS => {},
    //         }
    //     }
    // }
}

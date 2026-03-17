const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const builtin = @import("builtin");

const string = @cImport(@cInclude("string.h"));
const unistd = @cImport(@cInclude("unistd.h"));

previous_termios: std.posix.termios,

const Self = @This();
pub const Error = std.posix.TermiosGetError || std.posix.TermiosSetError;
const CSI = "\x1B[";

pub fn init() Error!Self {
    const stdin_handle = Io.File.stdin().handle;
    const previous_termios: std.posix.termios = try std.posix.tcgetattr(stdin_handle);

    var termios = previous_termios;
    termios.lflag.ICANON = false;
    termios.lflag.ECHO = false;

    termios.cc[@intFromEnum(std.posix.V.INTR)] = unistd._POSIX_VDISABLE;
    if (builtin.os.tag == .macos or builtin.os.tag == .freebsd) {
        termios.cc[@intFromEnum(std.posix.V.DSUSP)] = unistd._POSIX_VDISABLE;
        termios.cc[@intFromEnum(std.posix.V.SUSP)] = unistd._POSIX_VDISABLE;
    }

    try std.posix.tcsetattr(stdin_handle, std.posix.TCSA.NOW, termios);

    return Self{ .previous_termios = previous_termios };
}

pub fn deinit(self: Self) void {
    const stdin_handle = Io.File.stdin().handle;

    std.posix.tcsetattr(stdin_handle, std.posix.TCSA.NOW, self.previous_termios) catch {
        const errno_val = std.c._errno().*;
        const errno_string = string.strerror(errno_val);

        std.log.err("{s}\n", .{errno_string});
    };
}

// * send the query
// * advance the state machine until
//   - either the cursor position has been reported
//   - or we timeout (~20ms)

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

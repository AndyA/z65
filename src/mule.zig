const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const builtin = @import("builtin");

const POSIX = struct {
    const string = @cImport(@cInclude("string.h"));
    const unistd = @cImport(@cInclude("unistd.h"));

    previous_termios: std.posix.termios,

    const Self = @This();
    pub const Error = std.posix.TermiosGetError || std.posix.TermiosSetError;
    const CSI = "\x1B[";

    pub fn init() Error!Self {
        const stdin_handle = std.Io.File.stdin().handle;
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
        const stdin_handle = std.Io.File.stdin().handle;

        std.posix.tcsetattr(stdin_handle, std.posix.TCSA.NOW, self.previous_termios) catch {
            const errno_val = std.c._errno().*;
            const errno_string = string.strerror(errno_val);

            std.log.err("{s}\n", .{errno_string});
        };
    }

    pub fn getCursorPosition(self: Self, input: *Input) !void {
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
};

const Term = switch (builtin.os.tag) {
    .windows => @compileError("Sorry - no Windows support yet"),
    else => POSIX,
};

pub const KeyCode = enum(u8) {
    CURSOR_UP,
    CURSOR_DOWN,
    CURSOR_RIGHT,
    CURSOR_LEFT,
};

pub const InputState = struct {
    const Self = @This();

    chars: []const u8,
    pos: usize, // byte offset - utf8 ignorant

    pub fn init(gpa: Allocator, chars: []const u8, pos: usize) !Self {
        return Self{ .chars = try gpa.dupe(u8, chars), .pos = pos };
    }

    pub fn deinit(self: Self, gpa: Allocator) void {
        gpa.free(self.chars);
    }
};

pub const Input = struct {
    const Self = @This();
    const UndoSize = 100;

    io: Io,
    gpa: Allocator,

    term: Term,

    undo: std.Deque(InputState),

    in: Io.File,
    in_buf: [32]u8 = undefined,

    out: Io.File.Writer,
    out_buf: []u8,

    pub fn init(io: Io, gpa: Allocator) !Self {
        const out_buf = try gpa.alloc(u8, 16);

        return Self{
            .io = io,
            .gpa = gpa,
            .term = try .init(),
            .undo = try .initCapacity(gpa, UndoSize),
            .in = std.Io.File.stdin(),
            .out = std.Io.File.stdout().writer(io, out_buf),
            .out_buf = out_buf,
        };
    }

    pub fn deinit(self: *Self) void {
        while (self.undo.popBack()) |state| {
            state.deinit(self.gpa);
        }
        self.undo.deinit(self.gpa);
        self.gpa.free(self.out_buf);
        self.term.deinit();
    }

    pub fn readInput(self: *Self) ![]const u8 {
        const nread = try self.in.readStreaming(self.io, &.{&self.in_buf});
        return self.in_buf[0..nread];
    }

    pub fn writeAll(self: *Self, chars: []const u8) !void {
        try self.out.interface.writeAll(chars);
        try self.out.interface.flush();
    }
};

pub fn main(init: std.process.Init) !void {
    var input: Input = try .init(init.io, init.gpa);
    defer input.deinit();

    try input.term.getCursorPosition(&input);
    while (true) {
        const chars = try input.readInput();
        for (chars) |c| {
            print("{x:0>2} ", .{c});
        }
        for (chars) |c| {
            print("{c}", .{if (std.ascii.isPrint(c)) c else '.'});
        }
        print("\n", .{});
        if (chars.len > 0 and chars[0] == 0x03) break;
    }
}

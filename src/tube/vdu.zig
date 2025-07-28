const std = @import("std");
const serde = @import("../tools/serde.zig").serde;

fn MakePoint(T: type) type {
    return struct {
        const Self = @This();
        x: T = 0,
        y: T = 0,

        pub fn format(self: Self, writer: *std.io.Writer) std.io.Writer.Error!void {
            try writer.print("({d}, {d})", .{ self.x, self.y });
        }
    };
}

const TextPoint = MakePoint(u8);
const Point = MakePoint(i16);

const RGB = struct {
    const Self = @This();
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,

    pub fn format(self: Self, writer: *std.io.Writer) std.io.Writer.Error!void {
        try writer.print("({d}, {d}, {d})", .{ self.r, self.g, self.b });
    }
};

const NoOp = serde(struct {
    fn run(self: *@This(), vdu: *VDU) !void {
        _ = self;
        try vdu.writer.print("NoOp\n", .{});
    }
});

const NextToPrinter = serde(struct {
    char: u8,
    fn run(self: *@This(), vdu: *VDU) !void {
        try vdu.writer.print("NextToPrinter {d}\n", .{self.char});
    }
});

const TextColour = serde(struct {
    colour: u8,
    fn run(self: *@This(), vdu: *VDU) !void {
        try vdu.writer.print("TextColour {d}\n", .{self.colour});
    }
});

const GraphicsColour = serde(struct {
    mode: u8,
    colour: u8,
    fn run(self: *@This(), vdu: *VDU) !void {
        try vdu.writer.print("GraphicsColour {d}, {d}\n", .{ self.mode, self.colour });
    }
});

const LogicalColour = serde(struct {
    colour: u8,
    simple: u8,
    rgb: RGB,
    fn run(self: *@This(), vdu: *VDU) !void {
        try vdu.writer.print("LogicalColour {d}, {d}, {f}\n", .{ self.colour, self.simple, self.rgb });
    }
});

const ScreenMode = serde(struct {
    mode: u8,
    fn run(self: *@This(), vdu: *VDU) !void {
        vdu.mode = self.mode;
    }
});

const DefineChar = serde(struct {
    char: u8,
    defn: [8]u8,
    fn run(self: *@This(), vdu: *VDU) !void {
        _ = self;
        _ = vdu;
    }
});

const GraphicsWindow = serde(struct {
    bl: Point,
    tr: Point,
    fn run(self: *@This(), vdu: *VDU) !void {
        try vdu.writer.print("GraphicsWindow {f}, {f}\n", .{ self.bl, self.tr });
    }
});

const Plot = serde(struct {
    cmd: u8,
    pt: Point,
    fn run(self: *@This(), vdu: *VDU) !void {
        try vdu.writer.print("Plot {d}, {f}\n", .{ self.cmd, self.pt });
        vdu.old_pt = vdu.last_pt;
        vdu.last_pt = self.pt;
    }
});

const TextWindow = serde(struct {
    bl: TextPoint,
    tr: TextPoint,
    fn run(self: *@This(), vdu: *VDU) !void {
        try vdu.writer.print("TextWindow {f}, {f}\n", .{ self.bl, self.tr });
    }
});

const GraphicsOrigin = serde(struct {
    origin: Point,
    fn run(self: *@This(), vdu: *VDU) !void {
        try vdu.writer.print("GraphicsOrigin {f}\n", .{self.origin});
    }
});

const CursorPos = serde(struct {
    pos: TextPoint,
    fn run(self: *@This(), vdu: *VDU) !void {
        try vdu.writer.print("CursorPos {f}\n", .{self.pos});
    }
});

fn Echo(char: u8) type {
    return serde(struct {
        fn run(self: *@This(), vdu: *VDU) !void {
            _ = self;
            try vdu.writer.print("{c}", .{char});
        }
    });
}

fn Print(str: []const u8) type {
    return serde(struct {
        fn run(self: *@This(), vdu: *VDU) !void {
            _ = self;
            try vdu.writer.print("{s}", .{str});
        }
    });
}

const VDUDespatch = [_]type{
    NoOp, //   0 0 Does nothing
    NextToPrinter, //   1 1 Send next character to printer only
    NoOp, //   2 0 Enable printer
    NoOp, //   3 0 Disable printer
    NoOp, //   4 0 Write text at text cursor
    NoOp, //   5 0 Write text at graphics cursor
    NoOp, //   6 0 Enable VDU drivers
    Echo(7), //   7 0 Make a short beep (BEL)
    Echo(8), //   8 0 Move cursor back one character
    Echo(9), //   9 0 Move cursor forward one character
    Echo(10), //  10 0 Move cursor down one line
    Echo(11), //  11 0 Move cursor up one line
    Print("\x1b[2J"), //  12 0 Clear text area
    Echo(13), //  13 0 Carriage return
    NoOp, //  14 0 Paged mode on
    NoOp, //  15 0 Paged mode off
    NoOp, //  16 0 Clear graphics area
    TextColour, //  17 1 Define text colour
    GraphicsColour, //  18 2 Define graphics colour
    LogicalColour, //  19 5 Define logical colour
    NoOp, //  20 0 Restore default logical colours
    NoOp, //  21 0 Disable VDU drivers or delete current line
    ScreenMode, //  22 1 Select screen MODE
    DefineChar, //  23 9 Re-program display character
    GraphicsWindow, //  24 8 Define graphics window
    Plot, //  25 5 PLOT K,X,Y
    NoOp, //  26 0 Restore default windows
    Echo(27), //  27 0 ESCAPE value
    TextWindow, //  28 4 Define text window
    GraphicsOrigin, //  29 4 Define graphics origin
    NoOp, //  30 0 Home text cursor to top left of window
    CursorPos, //  31 2 Move text cursor to X,Y
};

fn max_bytes() comptime_int {
    var max = 0;
    for (VDUDespatch) |c|
        max = @max(max, c.byteSize);
    return max;
}

pub const VDUMaxBytes = max_bytes();

pub const VDU = struct {
    const Self = @This();
    writer: *std.io.Writer,
    cmd: u8 = 0xff,
    queue: [VDUMaxBytes]u8 = undefined,
    q_pos: u8 = 0,
    q_size: u8 = 0,

    mode: u8 = 0,
    old_pt: Point = Point{ .x = 0, .y = 0 },
    last_pt: Point = Point{ .x = 0, .y = 0 },

    pub fn init(writer: *std.io.Writer) Self {
        return Self{ .writer = writer };
    }
    pub fn peek8(self: Self, addr: u16) u8 {
        const pos: u8 = @intCast(addr);
        if (pos > self.q_size) @panic("Out of range");
        return self.queue[pos];
    }

    fn runCommand(self: *Self) !void {
        switch (self.cmd) {
            inline 0...VDUDespatch.len - 1 => |code| {
                var params = VDUDespatch[code].read(self, 0);
                try params.run(self);
            },
            else => @panic("Bad VDU code"),
        }
        self.reset();
    }

    pub fn reset(self: *Self) void {
        self.q_pos = 0;
        self.q_size = 0;
        self.cmd = 0xff;
    }

    pub fn oswrch(self: *Self, char: u8) !void {
        if (self.q_size != 0) {
            if (self.q_pos < VDUMaxBytes) self.queue[self.q_pos] = char;
            self.q_pos += 1;
            if (self.q_pos == self.q_size)
                try self.runCommand();
        } else {
            switch (char) {
                inline 0...VDUDespatch.len - 1 => |code| {
                    self.cmd = char;
                    self.q_size = VDUDespatch[code].byteSize;
                    if (self.q_size == 0)
                        try self.runCommand();
                },
                else => {
                    try self.writer.print("{c}", .{char});
                },
            }
        }
    }
};

test VDU {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(alloc, &buf);
    defer w.deinit();

    var vdu = VDU.init(&w.writer);
    try vdu.oswrch('A');
    try vdu.oswrch(22);
    try vdu.oswrch(7);
    try vdu.oswrch('B');

    var output = w.toArrayList();
    defer output.deinit(alloc);

    try std.testing.expectEqual(7, vdu.mode);
    try std.testing.expectEqualDeep("AB", output.items);
}

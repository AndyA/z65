const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;
const linen = @import("linen/linen.zig");
const Keyboard = @import("linen/Keyboard.zig");

fn onEscape(_: *anyopaque) void {
    print("Escape\n", .{});
}

pub fn main(init: std.process.Init) !void {
    // Set up our I/O implementation.
    var threaded: Io.Threaded = .init(init.gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const stdin = Io.File.stdin();
    const term = try linen.Term.init(.{ .stdin = stdin });
    defer term.deinit();

    // const clock: Io.Clock = .awake;
    print("Hit space to quit\n", .{});

    var io_buf: [32]u8 = undefined;
    var reader = stdin.reader(init.io, &io_buf);
    var kb_buf: [256]u8 = undefined;

    var kb: Keyboard = .init(io, &reader.interface, &kb_buf, .init(onEscape, &.{}));
    try kb.start();
    defer kb.stop();

    // var last_ts: i64 = 0;
    while (true) {
        if (kb.poll(.fromSeconds(1))) |c| {
            print("\\x{x:0>2}", .{c});
            if (c == 0x20) break;
        } else {
            print("* ", .{});
        }
    }

    print("Bye!\n", .{});
}

const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;
const linen = @import("linen/linen.zig");
const ansi = @import("linen/ansi.zig");

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

    var escape: Io.Event = .unset;

    // const clock: Io.Clock = .awake;
    print("Hit space to quit\n", .{});

    var in_buf: [32]u8 = undefined;
    var reader = stdin.reader(init.io, &in_buf);
    var kb_buf: [256]ansi.InputEvent = undefined;

    var engine: ansi.Engine = .init(io, &reader.interface, &kb_buf, &escape);
    try engine.start();
    defer engine.stop();

    // var last_ts: i64 = 0;
    main: while (true) {
        switch (engine.poll(.fromSeconds(5))) {
            .char => |c| {
                print("\\x{x:0>2}", .{c});
                if (c == 0x20) break :main;
            },
            .meta => |m| {
                print("meta {s}\n", .{@tagName(m)});
            },
            .escape => {
                print("Escape\n", .{});
                escape.reset();
            },
            .timeout => print(" *\n", .{}),
        }
    }

    print("Bye!\n", .{});
}

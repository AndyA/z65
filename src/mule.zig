const std = @import("std");
const print = std.debug.print;
const linen = @import("linen/linen.zig");

pub fn main(init: std.process.Init) !void {
    const stdin = std.Io.File.stdin();
    const term = try linen.Term.init(.{ .stdin = stdin });
    defer term.deinit();

    var io_buf: [1]u8 = undefined;
    var reader = stdin.reader(init.io, &io_buf);
    while (true) {
        var buf: [1]u8 = undefined;
        _ = try reader.interface.readSliceShort(&buf);
        print("{x:0>2} ", .{buf[0]});
        if (buf[0] == 0x20) break;
    }

    print("Bye!\n", .{});
}

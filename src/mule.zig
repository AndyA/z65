const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;
const linen = @import("linen/linen.zig");

const ReadResult = union(enum) {
    input: error{ EndOfStream, ReadFailed }!u8,
    timeout: error{Canceled}!void,
    shutdown: error{Canceled}!void,
};

fn readWithTimeout(io: Io, reader: *Io.Reader, timeout: ?Io.Duration) !ReadResult {
    var results: [10]ReadResult = undefined;
    var select = Io.Select(ReadResult).init(io, &results);
    defer _ = select.cancel();

    // _ = reader;
    select.async(.input, Io.Reader.takeByte, .{reader});

    if (timeout) |to| {
        select.async(.timeout, Io.Clock.Duration.sleep, .{
            .{ .raw = to, .clock = .awake },
            io,
        });
    }

    return try select.await();
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
    // var last_ts: i64 = 0;
    while (true) {
        const res = try readWithTimeout(io, &reader.interface, .fromSeconds(1));
        switch (res) {
            .input => |i| {
                const c = try i;
                print("\\x{x:0>2}", .{c});
                if (c == 0x20) break;
            },
            .shutdown => {},
            .timeout => print("* ", .{}),
        }
        // const c = try reader.interface.takeByte();
        // const ts = clock.now(init.io).toMilliseconds();
        // if (last_ts == 0) last_ts = ts;
        // const elapsed = ts - last_ts;
        // last_ts = ts;
        // if (elapsed > 10) print("\n", .{});
        // if (c == 0x20) break;
        // if (std.ascii.isPrint(c))
        //     print("{c}", .{c})
        // else
        //     print("\\x{x:0>2}", .{c});
    }

    print("Bye!\n", .{});
}

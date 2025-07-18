const std = @import("std");
const machine = @import("cpu/cpu.zig");
const memory = @import("cpu/memory.zig");
const ct = @import("cpu/cpu_tools.zig");
const tube = @import("tube.zig");
const hb = @import("hibasic.zig");

const TRACE: u16 = 0xfe90;

fn saveSnapshot(mc: hb.HiBasic, file: []const u8) !void {
    const prog = mc.getProgram();
    const file_handle = try std.fs.cwd().createFile(file, .{ .truncate = true });
    defer file_handle.close();
    try file_handle.writeAll(prog);
    std.debug.print("Saved snapshot to {s}\n", .{file});
}

fn loadSnapshot(mc: *hb.HiBasic, file: []const u8) !bool {
    var buf: [0x10000]u8 = undefined;
    const prog = std.fs.cwd().readFile(file, buf[0..]) catch |err| {
        if (err == error.FileNotFound) return false;
        return err;
    };
    @memcpy(mc.ram[0x800 .. 0x800 + prog.len], prog);
    // try mc.setProgram(prog);
    std.debug.print("Loaded snapshot from {s}. Type \"OLD\" to retrieve it.\n", .{file});
    return true;
}

pub fn main() !void {
    var r_buf: [256]u8 = undefined;
    var w_buf: [0]u8 = undefined;
    var r = std.fs.File.stdin().reader(&r_buf);
    var w = std.fs.File.stdout().writer(&w_buf);

    var trapper = try tube.TubeOS.init(
        std.heap.page_allocator,
        &r.interface,
        &w.interface,
    );
    defer trapper.deinit();

    var ram: [0x10000]u8 = @splat(0);
    var mc = try hb.HiBasic.init(&ram, &trapper);
    _ = try loadSnapshot(&mc, "tmp/snapshot.bbc");

    var cpu = mc.cpu;
    cpu.poke8(TRACE, 0x00); // disable tracing
    while (!cpu.stopped) {
        cpu.step();
        switch (cpu.peek8(TRACE)) {
            0x00 => {},
            0x01 => std.debug.print("{f}\n", .{cpu}),
            else => {},
        }
    }

    std.debug.print("\nBye!\n", .{});
    try saveSnapshot(mc, "tmp/snapshot.bbc");
}

test {
    @import("std").testing.refAllDecls(@This());
}

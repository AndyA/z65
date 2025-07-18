const std = @import("std");
const machine = @import("cpu/cpu.zig");
const memory = @import("cpu/memory.zig");
const ct = @import("cpu/cpu_tools.zig");
const tube = @import("tube.zig");
const hb = @import("hibasic.zig");

const TRACE: u16 = 0xfe90;

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

    var ram: [0x10000]u8 = @splat(0);
    const mc = try hb.HiBasic.init(&ram, &trapper);

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
}

test {
    @import("std").testing.refAllDecls(@This());
}

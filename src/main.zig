const std = @import("std");
const machine = @import("cpu/cpu.zig");
const memory = @import("cpu/memory.zig");
const tube = @import("tube/os.zig");
const hb = @import("hibasic.zig");

const TRACE: u16 = 0xfe90;
const SNAPSHOT = ".snapshot.bbc";

const TubeOS = tube.TubeOS(hb.HiBasic);

const Tube65C02 = machine.makeCPU(
    @import("cpu/wdc65c02.zig").InstructionSet65C02,
    @import("cpu/address_modes.zig").AddressModes,
    @import("cpu/instructions.zig").Instructions,
    @import("cpu/alu.zig").ALU65C02,
    memory.FlatMemory,
    machine.NullInterruptSource,
    TubeOS,
    .{ .clear_decimal_on_int = true },
);

pub fn main() !void {
    var r_buf: [256]u8 = undefined;
    var w_buf: [0]u8 = undefined;
    var r = std.fs.File.stdin().reader(&r_buf);
    var w = std.fs.File.stdout().writer(&w_buf);

    var ram: [0x10000]u8 = @splat(0);
    var lang = hb.HiBasic.init(&ram, SNAPSHOT);

    var os = try TubeOS.init(
        std.heap.page_allocator,
        &r.interface,
        &w.interface,
        &lang,
    );
    defer os.deinit();

    var cpu = Tube65C02.init(
        memory.FlatMemory{ .ram = &ram },
        machine.NullInterruptSource{},
        &os,
    );

    os.installInHost(&cpu);
    lang.installInHost(&cpu);

    cpu.poke8(TRACE, 0x00); // disable tracing
    while (!cpu.stopped) {
        cpu.step();
        switch (cpu.peek8(TRACE)) {
            0x00 => {},
            0x01 => std.debug.print("{f}\n", .{cpu}),
            else => {},
        }
    }

    try lang.shutDown(&cpu);
}

test {
    @import("std").testing.refAllDecls(@This());
}

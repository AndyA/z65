const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    @setEvalBranchQuota(4000);
    const memory = @import("memory.zig");
    const ints = @import("interrupts.zig");

    const M6502 = cpu.make6502(
        @import("address_modes.zig").AddressModes,
        @import("instructions.zig").Instructions,
        memory.FlatMemory,
        ints.NullInterruptSource,
        @import("mos6502.zig").INSTRUCTION_SET,
    );
    var ram: [0x10000]u8 = @splat(0);
    const mem = memory.FlatMemory{ .ram = &ram };
    var mc = M6502{
        .mem = mem,
        .int_source = ints.NullInterruptSource{},
        .PC = 0x8000,
    };

    mc.poke8(0x8000, 0xA2); // LDX #0
    mc.poke8(0x8001, 0x00);
    mc.poke8(0x8002, 0xA0); // LDY #0
    mc.poke8(0x8003, 0x00);
    mc.poke8(0x8004, 0xC8); // INY
    mc.poke8(0x8005, 0xD0); // BNE $8004
    mc.poke8(0x8006, 0xFD);
    mc.poke8(0x8007, 0xE8); // INX
    mc.poke8(0x8008, 0xD0); // BNE $8002
    mc.poke8(0x8009, 0xF8);
    mc.poke8(0x800A, 0x60); // RTS

    std.debug.print("{s}\n", .{mc});

    for (0..1000) |_| {
        mc.step();
        std.debug.print("{s}\n", .{mc});
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

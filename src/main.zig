const std = @import("std");
const cpu = @import("cpu.zig");
const memory = @import("memory.zig");

const Vanilla6502 = cpu.makeCPU(
    @import("mos6502.zig").INSTRUCTION_SET,
    @import("address_modes.zig").AddressModes,
    @import("instructions.zig").Instructions,
    memory.FlatMemory,
    cpu.NullInterruptSource,
    cpu.PanicTrapHandler,
);

pub fn main() !void {
    var ram: [0x10000]u8 = @splat(0);

    var mc = Vanilla6502.init(
        memory.FlatMemory{ .ram = &ram },
        cpu.NullInterruptSource{},
        cpu.PanicTrapHandler{},
    );

    mc.PC = 0x8000;
    mc.asm8(0xA2); // LDX #0
    mc.asm8(0x00);
    mc.asm8(0xA0); // LDY #0
    mc.asm8(0x00);
    mc.asm8(0xC8); // INY
    mc.asm8(0xD0); // BNE $8004
    mc.asm8(0xFD);
    mc.asm8(0xE8); // INX
    mc.asm8(0xD0); // BNE $8002
    mc.asm8(0xF8);
    mc.asm8(0x60); // RTS

    mc.PC = 0x8000;
    std.debug.print("{s}\n", .{mc});

    for (0..1000) |_| {
        mc.step();
        std.debug.print("{s}\n", .{mc});
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

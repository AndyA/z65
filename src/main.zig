const std = @import("std");
const cpu = @import("cpu.zig");
const memory = @import("memory.zig");

const InstructionSet = @import("mos6502.zig").InstructionSet6502;

const Vanilla6502 = cpu.makeCPU(
    InstructionSet,
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
    mc.asmi8(.@"LDX #", 0x00);
    mc.asmi8(.@"LDY #", 0x00);
    mc.asmi(.@"INY impl");
    mc.asmi8(.@"BNE rel", 0xfd);
    mc.asmi(.@"INX impl");
    mc.asmi8(.@"BNE rel", 0xf8);
    mc.asmi(.@"RTS impl");

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

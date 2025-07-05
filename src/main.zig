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
    mc.asmi(.@"LDX #");
    mc.asm8(0x00);
    mc.asmi(.@"LDY #");
    mc.asm8(0x00);
    mc.asmi(.@"INY impl");
    mc.asmi(.@"BNE rel");
    mc.asm8(0xFD);
    mc.asmi(.@"INX impl"); // INX
    mc.asmi(.@"BNE rel");
    mc.asm8(0xF8);
    mc.asmi(.@"RTS impl"); // RTS

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

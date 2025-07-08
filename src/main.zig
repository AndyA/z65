const std = @import("std");
const cpu = @import("cpu.zig");
const memory = @import("memory.zig");
const tt = @import("type_tools.zig");
const srec = @import("srec.zig");

pub const PORTAL_OP = 0xbb;

const Vanilla65C02 = cpu.makeCPU(
    @import("wdc65c02.zig").InstructionSet65C02,
    @import("address_modes.zig").AddressModes,
    @import("instructions.zig").Instructions,
    memory.FlatMemory,
    cpu.NullInterruptSource,
    cpu.PanicTrapHandler,
);

pub fn main() !void {
    var ram: [0x10000]u8 = @splat(0);

    var mc = Vanilla65C02.init(
        memory.FlatMemory{ .ram = &ram },
        cpu.NullInterruptSource{},
        cpu.PanicTrapHandler{},
    );

    mc.PC = 0x8000;
    mc.asmi8(.@"LDX #", 0x00);
    mc.asmi8(.@"LDY #", 0x00);
    mc.asmi(.INY);
    mc.asmi8(.@"BNE rel", 0xfd);
    mc.asmi(.INX);
    mc.asmi8(.@"BNE rel", 0xf8);
    mc.asmi(.RTS);

    mc.PC = 0x8000;
    std.debug.print("{s}\n", .{mc});

    for (0..10) |_| {
        mc.step();
        std.debug.print("{s}\n", .{mc});
    }
}

test {
    @import("std").testing.refAllDecls(@This());

    const line = "S119000A0000000000000000008001C38241007F001F71800FFF38";
    var rec = try srec.SRec.init(std.testing.allocator, line);
    defer rec.deinit();
}

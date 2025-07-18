const std = @import("std");
const machine = @import("cpu/cpu.zig");
const memory = @import("cpu/memory.zig");
const ct = @import("cpu/cpu_tools.zig");
const tube = @import("tube.zig");

const Tube65C02 = machine.makeCPU(
    @import("cpu/wdc65c02.zig").InstructionSet65C02,
    @import("cpu/address_modes.zig").AddressModes,
    @import("cpu/instructions.zig").Instructions,
    @import("cpu/alu.zig").ALU65C02,
    memory.FlatMemory,
    machine.NullInterruptSource,
    tube.TubeOS,
    .{ .clear_decimal_on_int = true },
);

pub const HiBasicError = error{
    ProgramTooLarge,
};

pub const HiBasic = struct {
    const Self = @This();
    const load_addr = @intFromEnum(tube.Symbols.HIMEM);
    cpu: Tube65C02,
    ram: *[0x10000]u8,

    const HIMEM = 0x06;
    const TOP = 0x12;
    const PAGE_HI = 0x18;

    pub fn init(ram: *[0x10000]u8, trapper: *tube.TubeOS) !Self {
        const rom_image = @embedFile("roms/HiBASIC.rom");
        @memcpy(ram[load_addr .. load_addr + rom_image.len], rom_image);

        var cpu = Tube65C02.init(
            memory.FlatMemory{ .ram = ram },
            machine.NullInterruptSource{},
            trapper,
        );

        trapper.installInHost(&cpu);

        var self = Self{ .cpu = cpu, .ram = ram };
        self.reset();

        return self;
    }

    pub fn reset(self: *Self) void {
        self.cpu.reset();
        self.cpu.PC = @intCast(load_addr);
        self.cpu.A = 0x01;
    }

    pub fn getProgram(self: Self) []const u8 {
        const page: u16 = @intCast(self.cpu.peek8(PAGE_HI) << 8);
        const top: u16 = self.cpu.peek16(TOP);
        return self.ram[page..top];
    }

    pub fn setProgram(self: *Self, prog: []const u8) !void {
        const page: u16 = @intCast(self.cpu.peek8(PAGE_HI) << 8);
        const top: u16 = @intCast(page + prog.len);
        const himem: u16 = self.cpu.peek16(HIMEM);
        if (top > himem)
            return HiBasicError.ProgramTooLarge;
        @memcpy(self.ram[page..top], prog);
        self.cpu.poke16(TOP, top);
    }
};

const TRACE: u16 = 0xfe90;

pub fn initInterface(buffer: []u8) std.io.Writer {
    return .{
        .vtable = &.{
            .drain = std.fs.File.Writer.drain,
            .sendFile = std.fs.File.Writer.sendFile,
        },
        .buffer = buffer,
    };
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

    var ram: [0x10000]u8 = @splat(0);
    const mc = try HiBasic.init(&ram, &trapper);

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

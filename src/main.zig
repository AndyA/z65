const std = @import("std");
const machine = @import("cpu.zig");
const memory = @import("memory.zig");
const ct = @import("cpu_tools.zig");
const tube = @import("tube.zig");

const Tube65C02 = machine.makeCPU(
    @import("wdc65c02.zig").InstructionSet65C02,
    @import("address_modes.zig").AddressModes,
    @import("instructions.zig").Instructions,
    @import("alu.zig").ALU65C02,
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

    pub fn init(ram: *[0x10000]u8, reader: *std.io.Reader, writer: *std.io.Writer) !Self {
        var trapper = try tube.TubeOS.init(
            std.heap.page_allocator,
            reader,
            writer,
        );

        const rom_image = @embedFile("roms/HiBASIC.rom");
        @memcpy(ram[load_addr .. load_addr + rom_image.len], rom_image);

        var cpu = Tube65C02.init(
            memory.FlatMemory{ .ram = ram },
            machine.NullInterruptSource{},
            &trapper,
        );

        tube.TubeOS.installInHost(&cpu);

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

pub fn main() !void {
    var r_buf: [256]u8 = undefined;
    var w_buf: [0]u8 = undefined;
    var r = std.fs.File.stdin().reader(&r_buf);
    var w = std.fs.File.stdout().writer(&w_buf);
    var ram: [0x10000]u8 = @splat(0);
    const mc = try HiBasic.init(&ram, &r.interface, &w.interface);

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

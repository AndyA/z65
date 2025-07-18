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

    // Some zero page locations used by HiBASIC
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

    pub fn getPage(self: Self) u16 {
        const page_hi: u16 = @intCast(self.cpu.peek8(PAGE_HI));
        const page: u16 = page_hi << 8;
        return page;
    }

    pub fn getProgram(self: Self) []const u8 {
        const page = self.getPage();
        const top: u16 = self.cpu.peek16(TOP);
        return self.ram[page..top];
    }

    pub fn setProgram(self: *Self, prog: []const u8) !void {
        const page = self.getPage();
        const top: u16 = @intCast(page + prog.len);
        const himem: u16 = self.cpu.peek16(HIMEM);
        std.debug.print("page={x}, top={x}, himem={x}\n", .{ page, top, himem });
        if (top > himem)
            return HiBasicError.ProgramTooLarge;
        @memcpy(self.ram[page..top], prog);
        self.cpu.poke16(TOP, top);
    }
};

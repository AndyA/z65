const std = @import("std");
const machine = @import("cpu.zig");
const memory = @import("memory.zig");
const tt = @import("type_tools.zig");
const srec = @import("srec.zig");

const TRAP_OPCODE: u8 = 0xBB;

const MOSFunction = enum(u8) {
    OSCLI = 1, // OSCLI
    OSBYTE,
    OSWORD,
    OSWRCH, // Write character
    OSRDCH, // Read character
    OSFILE,
    OSARGS,
    OSBGET,
    OSBPUT,
    OSGBPB, // Get Block, Put Block
    OSFIND, // Open file
};

const MOSVectors = enum(u16) {
    BRKV = 0x0202,
    IRQV = 0x0204,
    CLIV = 0x0208,
    BYTEV = 0x020A,
    WORDV = 0x020C,
    WRCHV = 0x020E,
    RDCHV = 0x0210,
    FILEV = 0x0212,
    ARGSV = 0x0214,
    BGETV = 0x0216,
    BPUTV = 0x0218,
    GBPBV = 0x021A,
    FINDV = 0x021C,
};

const PAGE = 0x800;
const HIMEM = 0xb800;
const MACHINE = 0x0000;

fn setXY(cpu: anytype, xy: u16) void {
    cpu.X = @intCast(xy & 0xff);
    cpu.Y = @intCast(xy >> 8);
}

fn getXY(cpu: anytype) u16 {
    return @as(u16, cpu.Y) << 8 | @as(u16, cpu.X);
}

const TubeTrapHandler = struct {
    pub const Self = @This();
    base_time_ms: i64,

    pub fn trap(self: *Self, cpu: anytype, opcode: u8) void {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn().reader();

        if (opcode == TRAP_OPCODE) {
            const osfn: MOSFunction = @enumFromInt(cpu.fetch8());
            switch (osfn) {
                .OSCLI => {
                    std.debug.print("OSCLI {s}\n", .{cpu});
                },
                .OSBYTE => {
                    switch (cpu.A) {
                        0x82 => setXY(cpu, MACHINE),
                        0x83 => setXY(cpu, PAGE),
                        0x84 => setXY(cpu, HIMEM),
                        else => std.debug.print("OSBYTE {x} not implemented {s}\n", .{ cpu.A, cpu }),
                    }
                },
                .OSWORD => {
                    const addr = getXY(cpu);
                    switch (cpu.A) {
                        0x00 => {
                            var buf: [256]u8 = undefined;
                            const res = stdin.readUntilDelimiter(&buf, '\n') catch unreachable;
                            var buf_addr = cpu.peek16(addr);
                            const max_len = cpu.peek8(addr + 2);
                            cpu.Y = @as(u8, @min(res.len, max_len));
                            cpu.P.C = false;
                            for (res, 0..) |c, i| {
                                if (i >= max_len) break;
                                cpu.poke8(buf_addr, c);
                                buf_addr += 1;
                            }
                            cpu.poke8(buf_addr, 0x0d);
                        },
                        0x01 => {
                            const delta_ms = std.time.milliTimestamp() - self.base_time_ms;
                            const delta_cs: u40 = @intCast(@divTrunc(delta_ms, 10));
                            cpu.poke16(addr + 0, @intCast(delta_cs & 0xffff));
                            cpu.poke16(addr + 2, @intCast((delta_cs >> 16) & 0xffff));
                            cpu.poke8(addr + 4, @intCast((delta_cs >> 32) & 0xff));
                        },
                        0x02 => {
                            const new_time_cs: u40 = cpu.peek16(addr + 0) |
                                @as(u40, cpu.peek16(addr + 2)) << 16 |
                                @as(u40, cpu.peek8(addr + 4)) << 32;
                            self.base_time_ms = std.time.milliTimestamp() - new_time_cs * 10;
                        },
                        else => std.debug.print("OSWORD {x} not implemented\n", .{cpu.A}),
                    }
                },
                .OSWRCH => {
                    stdout.print("{c}", .{cpu.A}) catch unreachable;
                },
                .OSRDCH => {
                    std.debug.print("OSRDCH {s}\n", .{cpu});
                },
                .OSFILE => {
                    std.debug.print("OSFILE {s}\n", .{cpu});
                },
                .OSARGS => {
                    std.debug.print("OSARGS {s}\n", .{cpu});
                },
                .OSBGET => {
                    std.debug.print("OSBGET {s}\n", .{cpu});
                },
                .OSBPUT => {
                    std.debug.print("OSBPUT {s}\n", .{cpu});
                },
                .OSGBPB => {
                    std.debug.print("OSGBPB {s}\n", .{cpu});
                },
                .OSFIND => {
                    std.debug.print("OSFIND {s}\n", .{cpu});
                },
            }
        } else {
            std.debug.print("Illegal instruction: {x} at {s}\n", .{ opcode, cpu });
            @panic("Illegal instruction");
        }
    }
};

const Vanilla65C02 = machine.makeCPU(
    @import("wdc65c02.zig").InstructionSet65C02,
    @import("address_modes.zig").AddressModes,
    @import("instructions.zig").Instructions,
    @import("alu.zig").ALU65C02,
    memory.FlatMemory,
    machine.NullInterruptSource,
    TubeTrapHandler,
    .{ .clear_decimal_on_int = true },
);

fn buildTubeOS(mc: *Vanilla65C02) void {
    mc.PC = 0xff00; // traps
    const STUB_START = 0xffca;

    // Build traps and populate vectors
    switch (@typeInfo(MOSFunction)) {
        .@"enum" => |info| {
            inline for (info.fields) |field| {
                const vec_name = field.name[2..] ++ "V";
                const vec_addr: u16 = @intFromEnum(@field(MOSVectors, vec_name));
                const trap_addr = mc.PC;
                mc.asm8(TRAP_OPCODE);
                mc.asm8(@intCast(field.value));
                mc.asmi(.RTS);
                mc.poke16(vec_addr, trap_addr);
            }
        },
        else => @panic("Invalid MOSFunction type"),
    }

    std.debug.assert(mc.PC <= STUB_START);
    mc.PC = STUB_START;
    const irq_addr = mc.PC;
    mc.asmi(.CLI);
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BRKV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.FINDV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.GBPBV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BPUTV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BGETV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.ARGSV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.FILEV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.RDCHV));
    std.debug.assert(mc.PC == 0xffe3);
    mc.asmi8(.@"CMP #", 0x0d);
    mc.asmi8(.@"BNE rel", 0x07); // 7 bytes to LFFEE
    mc.asmi8(.@"LDA #", 0x0a);
    mc.asmi16(.@"JSR abs", 0xffee);
    mc.asmi8(.@"LDA #", 0x0d);
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.WRCHV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.WORDV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BYTEV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.CLIV));
    std.debug.assert(mc.PC == 0xfffa);
    mc.poke16(Vanilla65C02.IRQV, irq_addr);
}

const HI_BASIC = @embedFile("roms/HiBASIC.rom");

pub fn main() !void {
    var ram: [0x10000]u8 = @splat(0);
    @memcpy(ram[HIMEM .. HIMEM + HI_BASIC.len], HI_BASIC);

    var trapper = TubeTrapHandler{ .base_time_ms = std.time.milliTimestamp() };

    var mc = Vanilla65C02.init(
        memory.FlatMemory{ .ram = &ram },
        machine.NullInterruptSource{},
        &trapper,
    );

    buildTubeOS(&mc);

    mc.PC = @intCast(HIMEM);
    mc.A = 0x01;
    std.debug.print("{s}\n", .{mc});

    while (!mc.stopped) {
        mc.step();
        // std.debug.print("{s}\n", .{mc});
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

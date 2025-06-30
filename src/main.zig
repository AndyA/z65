const std = @import("std");
const mos6502 = @import("mos6502.zig");
const memory = @import("memory.zig");
const constants = @import("constants.zig");

const STACK = constants.STACK;
const IRQV = constants.IRQV;
const RESETV = constants.RESETV;
const NMIV = constants.NMIV;

const C_BIT = constants.C_BIT;
const Z_BIT = constants.Z_BIT;
const I_BIT = constants.I_BIT;
const D_BIT = constants.D_BIT;
const B_BIT = constants.B_BIT;
const V_BIT = constants.V_BIT;
const N_BIT = constants.N_BIT;

pub fn make6502(comptime Memory: type, comptime opcodes: [256][]const u8) type {
    comptime {
        const AddressModes = @import("address_modes.zig").AddressModes;
        const Instructions = @import("instructions.zig").Instructions;

        var despatch: [256]fn (cpu: anytype) void = undefined;

        for (opcodes, 0..) |spec, opcode| {
            const space = std.mem.indexOfScalar(u8, spec, ' ') orelse @compileError("bad opcode");
            const mnemonic = spec[0..space];
            const addr_mode = spec[space + 1 ..];
            if (std.mem.eql(u8, addr_mode, "ill")) {
                const shim = struct {
                    pub fn instr(cpu: anytype) void {
                        std.debug.print("Illegal instruction {x} at {x}\n", .{ opcode, cpu.PC });
                    }
                };
                despatch[opcode] = shim.instr;
            } else if (@hasDecl(AddressModes, addr_mode)) {
                const addr_fn = @field(AddressModes, addr_mode);
                const inst_fn = @field(Instructions, mnemonic);
                const shim = struct {
                    pub fn instr(cpu: anytype) void {
                        const ea = addr_fn(cpu);
                        inst_fn(cpu, ea);
                    }
                };
                despatch[opcode] = shim.instr;
            } else {
                despatch[opcode] = @field(Instructions, mnemonic);
            }
        }

        return struct {
            A: u8 = 0,
            X: u8 = 0,
            Y: u8 = 0,
            S: u8 = 0,
            P: u8 = 0,
            PC: u16 = 0,
            mem: Memory,

            const Self = @This();

            pub fn peek8(self: *Self, addr: u16) u8 {
                return self.mem.peek8(addr);
            }

            pub fn poke8(self: *Self, addr: u16, value: u8) void {
                self.mem.poke8(addr, value);
            }

            pub fn peek16(self: *Self, addr: u16) u16 {
                const lo: u16 = @intCast(self.peek8(addr));
                const hi: u16 = @intCast(self.peek8(addr +% 1));
                return (hi << 8) | lo;
            }

            pub fn poke16(self: *Self, addr: u16, value: u16) void {
                self.poke8(addr, @intCast(value & 0x00FF));
                self.poke8(addr +% 1, @intCast((value >> 8) & 0x00FF));
            }

            pub fn fetch8(self: *Self) u8 {
                const byte = self.peek8(self.PC);
                // std.debug.print("{x:0>4}: {x:0>2}\n", .{ self.PC, byte });
                self.PC +%= 1;
                return byte;
            }

            pub fn fetch16(self: *Self) u16 {
                const lo: u16 = @intCast(self.fetch8());
                const hi: u16 = @intCast(self.fetch8());
                return (hi << 8) | lo;
            }

            pub fn push8(self: *Self, byte: u8) void {
                self.poke8(STACK | self.S, byte);
                self.S -%= 1;
            }

            pub fn pop8(self: *Self) u8 {
                self.S +%= 1;
                return self.peek8(STACK | self.S);
            }

            pub fn push16(self: *Self, value: u16) void {
                self.push8(@intCast((value >> 8) & 0x00FF));
                self.push8(@intCast(value & 0x00FF));
            }

            pub fn pop16(self: *Self) u16 {
                const lo: u16 = @intCast(self.pop8());
                const hi: u16 = @intCast(self.pop8());
                return (hi << 8) | lo;
            }

            pub fn reset(self: *Self) void {
                self.PC = self.mem.fetch16(RESETV);
                self.P = C_BIT | I_BIT;
            }

            pub fn step(self: *Self) void {
                const opcode = self.fetch8();
                switch (opcode) {
                    inline 0x00...0xff => |op| {
                        const instruction = despatch[op];
                        instruction(self);
                    },
                }
            }

            fn formatFlags(flags: u8, buf: *[8]u8) void {
                const off_flags = "nv0bdizc";
                const on_flags = "NV1BDIZC";
                var mask: u8 = 0x80;
                for (off_flags, 0..) |c, i| {
                    if (flags & mask != 0) {
                        buf[i] = on_flags[i];
                    } else {
                        buf[i] = c;
                    }
                    mask >>= 1;
                }
            }

            pub fn format(
                self: Self,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                _ = options;
                var flags_buf: [8]u8 = undefined;
                Self.formatFlags(self.P, &flags_buf);
                try writer.print("PC: {x:0>4} P: {s} A: {x:0>2} X: {x:0>2} Y: {x:0>2} S: {x:0>2}", .{
                    self.PC,
                    flags_buf,
                    self.A,
                    self.X,
                    self.Y,
                    self.S,
                });
            }
        };
    }
}

pub fn main() !void {
    @setEvalBranchQuota(4000);
    const M6502 = make6502(memory.FlatMemory, mos6502.INSTRUCTION_SET);
    var ram: [0x10000]u8 = @splat(0);
    const mem = memory.FlatMemory{ .ram = &ram };
    var mc = M6502{
        .mem = mem,
        .A = 0x00,
        .X = 0x00,
        .Y = 0x00,
        .S = 0xff,
        .P = C_BIT | I_BIT, // Set C and I flags
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

    mc.poke16(IRQV, 0x8000); // IRQ vector
    std.debug.print("{s}\n", .{mc});

    for (0..1000) |_| {
        mc.step();
        std.debug.print("{s}\n", .{mc});
    }
}

const std = @import("std");
const mos6502 = @import("mos6502.zig");

pub const STACK: u16 = 0x0100;
pub const IRQV: u16 = 0xfffe;
pub const RESETV: u16 = 0xfffc;
pub const NMIV: u16 = 0xfffa;

pub const C_BIT: u8 = 1 << 0;
pub const Z_BIT: u8 = 1 << 1;
pub const I_BIT: u8 = 1 << 2;
pub const D_BIT: u8 = 1 << 3;
pub const B_BIT: u8 = 1 << 4;
pub const V_BIT: u8 = 1 << 6;
pub const N_BIT: u8 = 1 << 7;

pub fn formatFlags(flags: u8, buf: *[8]u8) void {
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

pub fn makeMemory() type {
    return struct {
        ram: []u8,
        const Self = @This();

        pub fn poke8(self: *Self, addr: u16, value: u8) void {
            self.ram[addr] = value;
        }

        pub fn peek8(self: *Self, addr: u16) u8 {
            return self.ram[addr];
        }

        pub fn poke16(self: *Self, addr: u16, value: u16) void {
            self.poke8(addr, @intCast(value & 0x00FF));
            self.poke8(addr +% 1, @intCast((value >> 8) & 0x00FF));
        }

        pub fn peek16(self: *Self, addr: u16) u16 {
            const lo: u16 = @intCast(self.peek8(addr));
            const hi: u16 = @intCast(self.peek8(addr +% 1));
            return (hi << 8) | lo;
        }
    };
}

const Instructions = struct {
    const Self = @This();
    fn branch(comptime bit: u8, comptime want: bool, cpu: anytype, ea: u16) void {
        const set = (cpu.P & bit) != 0;
        if (set == want) {
            cpu.PC = ea;
        }
    }

    fn set_nz(cpu: anytype, byte: u8) u8 {
        const flags = (if (byte == 0) Z_BIT else 0) |
            (if (byte & 0x80 != 0) N_BIT else 0);
        cpu.P = (cpu.P & ~(Z_BIT | N_BIT)) | flags;
        return byte;
    }

    fn set_if(comptime bit: u8, cpu: anytype, value: bool) void {
        if (value) {
            cpu.P |= bit;
        } else {
            cpu.P &= ~bit;
        }
    }

    fn set_c(cpu: anytype, value: bool) void {
        Self.set_if(C_BIT, cpu, value);
    }

    fn set_v(cpu: anytype, value: bool) void {
        Self.set_if(V_BIT, cpu, value);
    }

    fn carry(comptime value: u8, cpu: anytype) u8 {
        const c_set = (cpu.P & C_BIT) != 0;
        if (c_set) {
            return value;
        } else {
            return 0x00;
        }
    }

    fn rol(cpu: anytype, byte: u8) u8 {
        const c_in = carry(0x01, cpu);
        Self.set_c(cpu, (byte & 0x80) != 0);
        return Self.set_nz(cpu, byte << 1 | c_in);
    }

    fn ror(cpu: anytype, byte: u8) u8 {
        const c_in = carry(0x80, cpu);
        Self.set_c(cpu, (byte & 0x01) != 0);
        return Self.set_nz(cpu, byte >> 1 | c_in);
    }

    fn shl(cpu: anytype, byte: u8) u8 {
        Self.set_c(cpu, (byte & 0x80) != 0);
        return Self.set_nz(cpu, byte << 1);
    }

    fn shr(cpu: anytype, byte: u8) u8 {
        Self.set_c(cpu, (byte & 0x01) != 0);
        return Self.set_nz(cpu, byte >> 1);
    }

    fn adc_binary(cpu: anytype, lhs: u8, rhs: u8) u8 {
        const c_in = carry(0x01, cpu);
        const result: u16 = @as(u16, lhs) + @as(u16, rhs) + @as(u16, c_in);
        Self.set_c(cpu, result & 0x100 != 0);
        Self.set_v(cpu, ((lhs ^ result) & (rhs ^ result) & 0x80) != 0);
        return Self.set_nz(cpu, @intCast(result & 0xff));
    }

    fn adc_decimal(cpu: anytype, lhs: u8, rhs: u8) u8 {
        var flags: u8 = 0;

        const c_in = carry(0x01, cpu);
        const bin_res: u8 = (lhs + rhs + c_in) & 0xff;
        if (bin_res == 0) flags |= Z_BIT;

        var dr_lo: u8 = (lhs & 0x0f) + (rhs & 0x0f) + c_in;
        var dr_hi: u8 = (lhs >> 4) + (rhs >> 4);
        if (dr_lo > 9) {
            dr_lo = (dr_lo - 10) & 0x0f;
            dr_hi += 1;
        }

        if (dr_hi & 0x08 != 0) flags |= N_BIT;
        if ((lhs ^ rhs & 0x80 == 0) and ((lhs ^ (dr_hi << 4)) & 0x80 != 0))
            flags |= V_BIT;

        if (dr_hi > 9) {
            dr_hi -= 10;
            dr_hi &= 0x0f;
            flags |= C_BIT;
        }

        cpu.P = (cpu.P & ~(Z_BIT | N_BIT | V_BIT | C_BIT)) | flags;
        return @as(u8, (dr_hi << 4) | dr_lo);
    }

    fn sbc_decimal(cpu: anytype, lhs: u8, rhs: u8) u8 {
        var flags: u8 = 0;
        const c_in = carry(0x01, cpu);

        const bin_res: u16 = (@as(u16, lhs) -% @as(u16, rhs) -% 1 +% @as(u16, c_in));
        if (bin_res & 0x80 != 0) flags |= N_BIT;
        if (bin_res & 0xff == 0) flags |= Z_BIT;
        if ((lhs ^ bin_res) & (rhs ^ bin_res) & 0x80 != 0) flags |= V_BIT;
        if (bin_res & 0x100 != 0) flags |= C_BIT;

        cpu.P = (cpu.P & ~(Z_BIT | N_BIT | V_BIT | C_BIT)) | flags;

        var dr_lo: u8 = (lhs & 0x0f) -% (rhs & 0x0f) -% 1 +% c_in;
        var dr_hi: u8 = (lhs >> 4) -% (rhs >> 4);

        if (dr_lo & 0x10 != 0) {
            dr_lo = (dr_lo -% 6) & 0x0f;
            dr_hi -= 1;
        }

        if (dr_hi & 0x10 != 0) {
            dr_hi = (dr_hi -% 6) & 0x0f;
        }

        return 0;
    }

    fn adc(cpu: anytype, lhs: u8, rhs: u8) u8 {
        if (cpu.P & D_BIT == 0) {
            return Self.adc_binary(cpu, lhs, rhs);
        } else {
            return Self.adc_decimal(cpu, lhs, rhs);
        }
    }

    fn sbc(cpu: anytype, lhs: u8, rhs: u8) u8 {
        if (cpu.P & D_BIT == 0) {
            return Self.adc_binary(cpu, lhs, rhs ^ 0xff);
        } else {
            return Self.sbc_decimal(cpu, lhs, rhs);
        }
    }

    fn cmp(cpu: anytype, lhs: u8, rhs: u8) void {
        Self.set_c(cpu, true);
        _ = Self.adc_binary(cpu, lhs, rhs ^ 0xff);
    }

    pub fn ADC(cpu: anytype, ea: u16) void {
        cpu.A = Self.adc(cpu, cpu.A, cpu.mem.peek8(ea));
    }

    pub fn AND(cpu: anytype, ea: u16) void {
        cpu.A = Self.set_nz(cpu, cpu.A & cpu.mem.peek8(ea));
    }

    pub fn ASL(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, Self.shl(cpu, cpu.mem.peek8(ea)));
    }

    pub fn ASLA(cpu: anytype) void {
        cpu.A = Self.shl(cpu, cpu.A);
    }

    pub fn BCC(cpu: anytype, ea: u16) void {
        Self.branch(C_BIT, false, cpu, ea);
    }

    pub fn BCS(cpu: anytype, ea: u16) void {
        Self.branch(C_BIT, true, cpu, ea);
    }

    pub fn BEQ(cpu: anytype, ea: u16) void {
        Self.branch(Z_BIT, true, cpu, ea);
    }

    pub fn BIT(cpu: anytype, ea: u16) void {
        const byte = cpu.A & cpu.mem.peek8(ea);
        const flags = (if (byte == 0) Z_BIT else 0) |
            (if (byte & 0x80 != 0) N_BIT else 0) |
            (if (byte & 0x40 != 0) V_BIT else 0);
        cpu.P = (cpu.P & ~(Z_BIT | N_BIT | V_BIT)) | flags;
    }

    pub fn BMI(cpu: anytype, ea: u16) void {
        Self.branch(N_BIT, true, cpu, ea);
    }

    pub fn BNE(cpu: anytype, ea: u16) void {
        Self.branch(Z_BIT, false, cpu, ea);
    }

    pub fn BPL(cpu: anytype, ea: u16) void {
        Self.branch(N_BIT, false, cpu, ea);
    }

    pub fn BRK(cpu: anytype) void {
        cpu.push16(cpu.PC);
        Self.PHP(cpu);
        cpu.P |= B_BIT | I_BIT; // Set B and I flags
        cpu.PC = cpu.mem.peek16(IRQV);
    }

    pub fn BVC(cpu: anytype, ea: u16) void {
        Self.branch(V_BIT, false, cpu, ea);
    }

    pub fn BVS(cpu: anytype, ea: u16) void {
        Self.branch(V_BIT, true, cpu, ea);
    }

    pub fn CLC(cpu: anytype) void {
        cpu.P &= ~C_BIT;
    }

    pub fn CLD(cpu: anytype) void {
        cpu.P &= ~D_BIT;
    }

    pub fn CLI(cpu: anytype) void {
        cpu.P &= ~I_BIT;
    }

    pub fn CLV(cpu: anytype) void {
        cpu.P &= ~V_BIT;
    }

    pub fn CMP(cpu: anytype, ea: u16) void {
        Self.cmp(cpu, cpu.A, cpu.mem.peek8(ea));
    }

    pub fn CPX(cpu: anytype, ea: u16) void {
        Self.cmp(cpu, cpu.X, cpu.mem.peek8(ea));
    }

    pub fn CPY(cpu: anytype, ea: u16) void {
        Self.cmp(cpu, cpu.Y, cpu.mem.peek8(ea));
    }

    pub fn DEC(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, Self.set_nz(cpu, cpu.mem.peek8(ea) -% 1));
    }

    pub fn DEX(cpu: anytype) void {
        cpu.X = Self.set_nz(cpu, cpu.X -% 1);
    }

    pub fn DEY(cpu: anytype) void {
        cpu.Y = Self.set_nz(cpu, cpu.Y -% 1);
    }

    pub fn EOR(cpu: anytype, ea: u16) void {
        cpu.A = Self.set_nz(cpu, cpu.A ^ cpu.mem.peek8(ea));
    }

    pub fn INC(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, Self.set_nz(cpu, cpu.mem.peek8(ea) +% 1));
    }

    pub fn INX(cpu: anytype) void {
        cpu.X = Self.set_nz(cpu, cpu.X +% 1);
    }

    pub fn INY(cpu: anytype) void {
        cpu.Y = Self.set_nz(cpu, cpu.Y +% 1);
    }

    pub fn JMP(cpu: anytype, ea: u16) void {
        cpu.PC = ea;
    }

    pub fn JSR(cpu: anytype, ea: u16) void {
        cpu.push16(cpu.PC -% 1);
        cpu.PC = ea;
    }

    pub fn LDA(cpu: anytype, ea: u16) void {
        cpu.A = Self.set_nz(cpu, cpu.mem.peek8(ea));
    }

    pub fn LDX(cpu: anytype, ea: u16) void {
        cpu.X = Self.set_nz(cpu, cpu.mem.peek8(ea));
    }

    pub fn LDY(cpu: anytype, ea: u16) void {
        cpu.Y = Self.set_nz(cpu, cpu.mem.peek8(ea));
    }

    pub fn LSR(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, Self.shr(cpu, cpu.mem.peek8(ea)));
    }

    pub fn LSRA(cpu: anytype) void {
        cpu.A = Self.shr(cpu, cpu.A);
    }

    pub fn NOP(cpu: anytype) void {
        _ = cpu;
    }

    pub fn ORA(cpu: anytype, ea: u16) void {
        cpu.A = Self.set_nz(cpu, cpu.A | cpu.mem.peek8(ea));
    }

    pub fn PHA(cpu: anytype) void {
        cpu.push8(cpu.A);
    }

    pub fn PHP(cpu: anytype) void {
        cpu.push8(cpu.P);
    }
    pub fn PLA(cpu: anytype) void {
        cpu.A = Self.set_nz(cpu, cpu.pop8());
    }
    pub fn PLP(cpu: anytype) void {
        cpu.P = cpu.pop8();
    }

    pub fn ROL(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, Self.rol(cpu, cpu.mem.peek8(ea)));
    }

    pub fn ROLA(cpu: anytype) void {
        cpu.A = Self.rol(cpu, cpu.A);
    }

    pub fn ROR(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, Self.ror(cpu, cpu.mem.peek8(ea)));
    }

    pub fn RORA(cpu: anytype) void {
        cpu.A = Self.ror(cpu, cpu.A);
    }

    pub fn RTI(cpu: anytype) void {
        Self.PLP(cpu);
        cpu.PC = cpu.pop16();
    }

    pub fn RTS(cpu: anytype) void {
        cpu.PC = cpu.pop16() +% 1;
    }

    pub fn SBC(cpu: anytype, ea: u16) void {
        cpu.A = Self.sbc(cpu, cpu.A, cpu.mem.peek8(ea));
    }

    pub fn SEC(cpu: anytype) void {
        cpu.P |= C_BIT;
    }

    pub fn SED(cpu: anytype) void {
        cpu.P |= D_BIT;
    }

    pub fn SEI(cpu: anytype) void {
        cpu.P |= I_BIT;
    }

    pub fn STA(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, cpu.A);
    }

    pub fn STX(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, cpu.X);
    }

    pub fn STY(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, cpu.Y);
    }

    pub fn TAX(cpu: anytype) void {
        cpu.X = Self.set_nz(cpu, cpu.A);
    }

    pub fn TAY(cpu: anytype) void {
        cpu.Y = Self.set_nz(cpu, cpu.A);
    }

    pub fn TSX(cpu: anytype) void {
        cpu.X = Self.set_nz(cpu, cpu.S);
    }

    pub fn TXA(cpu: anytype) void {
        cpu.A = Self.set_nz(cpu, cpu.X);
    }

    pub fn TXS(cpu: anytype) void {
        cpu.S = cpu.X;
    }

    pub fn TYA(cpu: anytype) void {
        cpu.A = Self.set_nz(cpu, cpu.Y);
    }
};

const AddressModes = struct {
    const Self = @This();
    fn zp16(cpu: anytype, zp: u8) u16 {
        const lo: u16 = @intCast(cpu.mem.peek8(zp));
        const hi: u16 = @intCast(cpu.mem.peek8(zp +% 1));
        return @as(u16, (hi << 8) | lo);
    }

    pub fn @"#"(cpu: anytype) u16 {
        const addr = cpu.PC;
        _ = cpu.fetch8();
        return addr;
    }

    pub fn @"X,ind"(cpu: anytype) u16 {
        const zp = cpu.fetch8();
        return Self.zp16(cpu, zp +% cpu.X);
    }

    pub fn abs(cpu: anytype) u16 {
        return cpu.fetch16();
    }

    pub fn @"abs,X"(cpu: anytype) u16 {
        return cpu.fetch16() +% cpu.X;
    }

    pub fn @"abs,Y"(cpu: anytype) u16 {
        return cpu.fetch16() +% cpu.Y;
    }

    pub fn ind(cpu: anytype) u16 {
        // Simulate JMP () bug
        const lo_addr = cpu.fetch16();
        var hi_addr: u16 = lo_addr +% 1;
        if (hi_addr & 0x00FF == 0x0000) {
            hi_addr -= 0x0100;
        }
        const lo: u16 = @intCast(cpu.mem.peek8(lo_addr));
        const hi: u16 = @intCast(cpu.mem.peek8(hi_addr));
        return @as(u16, (hi << 8) | lo);
    }

    pub fn @"ind,Y"(cpu: anytype) u16 {
        const zp = cpu.fetch8();
        return Self.zp16(cpu, zp) +% cpu.Y;
    }

    pub fn rel(cpu: anytype) u16 {
        const offset: i8 = @bitCast(cpu.fetch8());
        const base: i16 = @bitCast(cpu.PC);
        return @bitCast(base +% offset);
    }

    pub fn zpg(cpu: anytype) u16 {
        return @intCast(cpu.fetch8());
    }

    pub fn @"zpg,X"(cpu: anytype) u16 {
        return @intCast(cpu.fetch8() +% cpu.X);
    }

    pub fn @"zpg,Y"(cpu: anytype) u16 {
        return @intCast(cpu.fetch8() +% cpu.Y);
    }
};

pub fn make6502(comptime Memory: type, comptime opcodes: [256][]const u8) type {
    comptime {
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

            pub fn fetch8(self: *Self) u8 {
                const byte = self.mem.peek8(self.PC);
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
                self.mem.poke8(STACK | self.S, byte);
                self.S -%= 1;
            }

            pub fn pop8(self: *Self) u8 {
                self.S +%= 1;
                return self.mem.peek8(STACK | self.S);
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

            pub fn format(
                self: Self,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                _ = options;
                var flags_buf: [8]u8 = undefined;
                formatFlags(self.P, &flags_buf);
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
    const Memory = makeMemory();
    const M6502 = make6502(Memory, mos6502.INSTRUCTION_SET);
    var ram: [0x10000]u8 = @splat(0);
    var mem = Memory{ .ram = &ram };
    var mc = M6502{
        .mem = mem,
        .A = 0x00,
        .X = 0x00,
        .Y = 0x00,
        .S = 0xff,
        .P = C_BIT | I_BIT, // Set C and I flags
        .PC = 0x8000,
    };

    mem.poke8(0x8000, 0xA2); // LDX #0
    mem.poke8(0x8001, 0x00);
    mem.poke8(0x8002, 0xA0); // LDY #0
    mem.poke8(0x8003, 0x00);
    mem.poke8(0x8004, 0xC8); // INY
    mem.poke8(0x8005, 0xD0); // BNE $8004
    mem.poke8(0x8006, 0xFD);
    mem.poke8(0x8007, 0xE8); // INX
    mem.poke8(0x8008, 0xD0); // BNE $8002
    mem.poke8(0x8009, 0xF8);
    mem.poke8(0x800A, 0x60); // RTS

    mem.poke16(IRQV, 0x8000); // IRQ vector
    std.debug.print("{s}\n", .{mc});

    for (0..1000) |_| {
        mc.step();
        std.debug.print("{s}\n", .{mc});
    }
}

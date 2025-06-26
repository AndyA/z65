const std = @import("std");
const C = @import("const.zig");
const mos6502 = @import("mos6502.zig");

pub fn makeMemory() type {
    return struct {
        M: [0x10000]u8, // 64K memory
        const Self = @This();

        pub fn poke8(self: *Self, addr: u16, value: u8) void {
            self.M[addr] = value;
        }

        pub fn peek8(self: *Self, addr: u16) u8 {
            return self.M[addr];
        }

        pub fn poke16(self: *Self, addr: u16, value: u16) void {
            self.poke8(addr, @intCast(value & 0x00FF));
            self.poke8(addr +% 1, @intCast((value >> 8) & 0x00FF));
        }

        pub fn peek16(self: *Self, addr: u16) u16 {
            const lo: u16 = @intCast(self.peek8(addr));
            const hi: u16 = @intCast(self.peek8(addr +% 1));
            return @as(u16, (hi << 8) | lo);
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
        const flags = if (byte == 0) C.Z_BIT else 0 | if (byte & 0x80 != 0) C.N_BIT else 0;
        cpu.P = (cpu.P & ~(C.Z_BIT | C.N_BIT)) | flags;
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
        Self.set_if(C.C_BIT, cpu, value);
    }

    fn set_v(cpu: anytype, value: bool) void {
        Self.set_if(C.V_BIT, cpu, value);
    }

    fn shl(comptime rotate: bool, cpu: anytype, byte: u8) u8 {
        const c_out = (byte & 0x80) != 0;
        const result = byte << 1 | if (rotate and cpu.P & C.C_BIT) 1 else 0;
        Self.set_c(cpu, c_out);
        return Self.set_nz(cpu, result);
    }

    fn shr(comptime rotate: bool, cpu: anytype, byte: u8) u8 {
        const c_out = (byte & 0x01) != 0;
        const result = byte >> 1 | if (rotate and cpu.P & C.C_BIT) 0x80 else 0;
        Self.set_c(cpu, c_out);
        return Self.set_nz(cpu, result);
    }

    fn adc_binary(cpu: anytype, lhs: u8, rhs: u8) u8 {
        const c_in = if (cpu.P & C.C_BIT != 0) 1 else 0;
        const result: u16 = @as(u16, lhs) + @as(u16, rhs) + c_in;
        Self.set_c(cpu, result & 0x100 != 0);
        Self.set_v(cpu, ((lhs ^ result) & (rhs ^ result) & 0x80) != 0);
        return Self.set_nz(cpu, @bitCast(result & 0xff));
    }

    fn adc_decimal(cpu: anytype, lhs: u8, rhs: u8) u8 {
        const c_in0: u8 = if (cpu.P & C.C_BIT != 0) 1 else 0;
        const l0 = lhs & 0x0f;
        const l1 = (lhs >> 4) & 0x0f;
        const r0 = rhs & 0x0f;
        const r1 = (rhs >> 4) & 0x0f;
        var res0 = l0 + r0 + c_in0;
        var c_in1 = 0;
        if (res0 > 9) {
            c_in1 = res0 - 10;
            res0 -= 10;
        }
        var c_in2 = 0;
        var res1 = l1 + r1 + c_in1;
        if (res1 > 9) {
            c_in2 = res1 - 10;
            res1 -= 10;
        }
        const result: u8 = @bitCast((res1 << 4) | res0);
        Self.set_c(cpu, c_in2 != 0);
        Self.set_v(cpu, ((lhs ^ result) & (rhs ^ result) & 0x80) != 0);
        return Self.set_nz(cpu, result);
    }

    fn adc(cpu: anytype, lhs: u8, rhs: u8) u8 {
        if (cpu.P & C.D_BIT == 0) {
            return Self.adc_binary(cpu, lhs, rhs);
        } else {
            return Self.adc_decimal(cpu, lhs, rhs);
        }
    }

    fn sbc(cpu: anytype, lhs: u8, rhs: u8) u8 {
        return Self.adc(cpu, lhs, rhs ^ 0xff);
    }

    fn cmp(cpu: anytype, lhs: u8, rhs: u8) u8 {
        _ = Self.adc_binary(cpu, lhs, rhs ^ 0xff);
    }

    pub fn ADC(cpu: anytype, ea: u16) void {
        cpu.A = Self.adc(cpu, cpu.A, cpu.mem.peek8(ea));
    }

    pub fn AND(cpu: anytype, ea: u16) void {
        cpu.A = Self.set_nz(cpu, cpu.A & cpu.mem.peek8(ea));
    }

    pub fn ASL(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, Self.shl(false, cpu, cpu.mem.peek8(ea)));
    }

    pub fn ASLA(cpu: anytype) void {
        cpu.A = Self.shl(false, cpu, cpu.A);
    }

    pub fn BCC(cpu: anytype, ea: u16) void {
        Self.branch(C.C_BIT, false, cpu, ea);
    }

    pub fn BCS(cpu: anytype, ea: u16) void {
        Self.branch(C.C_BIT, true, cpu, ea);
    }

    pub fn BEQ(cpu: anytype, ea: u16) void {
        Self.branch(C.Z_BIT, true, cpu, ea);
    }

    pub fn BIT(cpu: anytype, ea: u16) void {
        const byte = cpu.A & cpu.mem.peek8(ea);
        const flags = (if (byte == 0) C.Z_BIT else 0) |
            (if (byte & 0x80 != 0) C.N_BIT else 0) |
            (if (byte & 0x40 != 0) C.V_BIT else 0);
        cpu.P = (cpu.P & ~(C.Z_BIT | C.N_BIT | C.V_BIT)) | flags;
    }

    pub fn BMI(cpu: anytype, ea: u16) void {
        Self.branch(C.N_BIT, true, cpu, ea);
    }

    pub fn BNE(cpu: anytype, ea: u16) void {
        Self.branch(C.Z_BIT, false, cpu, ea);
    }

    pub fn BPL(cpu: anytype, ea: u16) void {
        Self.branch(C.N_BIT, false, cpu, ea);
    }

    pub fn BRK(cpu: anytype) void {
        cpu.push16(cpu.PC);
        Self.PHP(cpu);
        cpu.P |= C.B_BIT | C.I_BIT; // Set B and I flags
        cpu.PC = cpu.mem.peek16(C.IRQV);
    }

    pub fn BVC(cpu: anytype, ea: u16) void {
        Self.branch(C.V_BIT, false, cpu, ea);
    }

    pub fn BVS(cpu: anytype, ea: u16) void {
        Self.branch(C.V_BIT, true, cpu, ea);
    }

    pub fn CLC(cpu: anytype) void {
        cpu.P &= ~C.C_BIT;
    }

    pub fn CLD(cpu: anytype) void {
        cpu.P &= ~C.D_BIT;
    }

    pub fn CLI(cpu: anytype) void {
        cpu.P &= ~C.I_BIT;
    }

    pub fn CLV(cpu: anytype) void {
        cpu.P &= ~C.V_BIT;
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
        cpu.mem.poke8(ea, Self.shr(false, cpu, cpu.mem.peek8(ea)));
    }

    pub fn LSRA(cpu: anytype) void {
        cpu.A = Self.shr(false, cpu, cpu.A);
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
        cpu.mem.poke8(ea, Self.shl(true, cpu, cpu.mem.peek8(ea)));
    }

    pub fn ROLA(cpu: anytype) void {
        cpu.A = Self.shl(true, cpu, cpu.A);
    }

    pub fn ROR(cpu: anytype, ea: u16) void {
        cpu.mem.poke8(ea, Self.shr(true, cpu, cpu.mem.peek8(ea)));
    }

    pub fn RORA(cpu: anytype) void {
        cpu.A = Self.shr(true, cpu, cpu.A);
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
        cpu.P |= C.C_BIT;
    }

    pub fn SED(cpu: anytype) void {
        cpu.P |= C.D_BIT;
    }

    pub fn SEI(cpu: anytype) void {
        cpu.P |= C.I_BIT;
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
        cpu.X = Self.set_nz(cpu, cpu.SP);
    }

    pub fn TXA(cpu: anytype) void {
        cpu.A = Self.set_nz(cpu, cpu.X);
    }

    pub fn TXS(cpu: anytype) void {
        cpu.SP = cpu.X;
    }

    pub fn TYA(cpu: anytype) void {
        cpu.A = Self.set_nz(cpu, cpu.Y);
    }
};

const AddressModes = struct {
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
        return AddressModes.zp16(cpu, zp +% cpu.X);
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
        return AddressModes.zp16(cpu, zp) +% cpu.Y;
    }

    pub fn rel(cpu: anytype) u16 {
        const base = cpu.PC;
        const offset: i8 = @intCast(cpu.fetch8());
        return base +% offset;
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
                const byte = self.peek8(self.PC);
                self.PC +%= 1;
                return byte;
            }

            pub fn fetch16(self: *Self) u16 {
                const lo: u8 = self.fetch8();
                const hi: u8 = self.fetch8();
                return @as(u16, (hi << 8) | lo);
            }

            pub fn push8(self: *Self, byte: u8) void {
                self.mem.poke8(0x0100 + u16(self.S), byte);
                self.S -%= 1;
            }

            pub fn pop8(self: *Self) u8 {
                self.S +%= 1;
                return self.mem.peek8(0x0100 + u16(self.S));
            }

            pub fn push16(self: *Self, value: u16) void {
                self.push8(@intCast((value >> 8) & 0x00FF));
                self.push8(@intCast(value & 0x00FF));
            }

            pub fn pop16(self: *Self) u16 {
                const lo: u8 = self.pop8();
                const hi: u8 = self.pop8();
                return @as(u16, (hi << 8) | lo);
            }

            pub fn reset(self: *Self) void {
                self.PC = self.mem.fetch16(C.RESETV);
            }

            pub fn step(self: *Self) void {
                const opcode = self.fetch8();
                const instruction = despatch[opcode];
                instruction(self);
            }
        };
    }
}

pub fn main() !void {
    @setEvalBranchQuota(4000);
    const Memory = makeMemory();
    const M6502 = make6502(Memory, mos6502.instruction_set);
    _ = M6502;
}

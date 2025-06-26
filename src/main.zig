const std = @import("std");

const IRQV = 0xfffe;
const RESETV = 0xfffc;
const NMIV = 0xfffa;

const C_BIT = 1 << 0;
const Z_BIT = 1 << 1;
const I_BIT = 1 << 2;
const D_BIT = 1 << 3;
const B_BIT = 1 << 4;
const V_BIT = 1 << 6;
const N_BIT = 1 << 7;

const instruction_set = [_][]const u8{
    "BRK impl", // 00
    "ORA X,ind", // 01
    "X02 ill", // 02
    "X03 ill", // 03
    "X04 ill", // 04
    "ORA zpg", // 05
    "ASL zpg", // 06
    "X07 ill", // 07
    "PHP impl", // 08
    "ORA #", // 09
    "ASLA impl", // 0a
    "X0B ill", // 0b
    "X0C ill", // 0c
    "ORA abs", // 0d
    "ASL abs", // 0e
    "X0F ill", // 0f
    "BPL rel", // 10
    "ORA ind,Y", // 11
    "X12 ill", // 12
    "X13 ill", // 13
    "X14 ill", // 14
    "ORA zpg,X", // 15
    "ASL zpg,X", // 16
    "X17 ill", // 17
    "CLC impl", // 18
    "ORA abs,Y", // 19
    "X1A ill", // 1a
    "X1B ill", // 1b
    "X1C ill", // 1c
    "ORA abs,X", // 1d
    "ASL abs,X", // 1e
    "X1F ill", // 1f
    "JSR abs", // 20
    "AND X,ind", // 21
    "X22 ill", // 22
    "X23 ill", // 23
    "BIT zpg", // 24
    "AND zpg", // 25
    "ROL zpg", // 26
    "X27 ill", // 27
    "PLP impl", // 28
    "AND #", // 29
    "ROLA impl", // 2a
    "X2B ill", // 2b
    "BIT abs", // 2c
    "AND abs", // 2d
    "ROL abs", // 2e
    "X2F ill", // 2f
    "BMI rel", // 30
    "AND ind,Y", // 31
    "X32 ill", // 32
    "X33 ill", // 33
    "X34 ill", // 34
    "AND zpg,X", // 35
    "ROL zpg,X", // 36
    "X37 ill", // 37
    "SEC impl", // 38
    "AND abs,Y", // 39
    "X3A ill", // 3a
    "X3B ill", // 3b
    "X3C ill", // 3c
    "AND abs,X", // 3d
    "ROL abs,X", // 3e
    "X3F ill", // 3f
    "RTI impl", // 40
    "EOR X,ind", // 41
    "X42 ill", // 42
    "X43 ill", // 43
    "X44 ill", // 44
    "EOR zpg", // 45
    "LSR zpg", // 46
    "X47 ill", // 47
    "PHA impl", // 48
    "EOR #", // 49
    "LSRA impl", // 4a
    "X4B ill", // 4b
    "JMP abs", // 4c
    "EOR abs", // 4d
    "LSR abs", // 4e
    "X4F ill", // 4f
    "BVC rel", // 50
    "EOR ind,Y", // 51
    "X52 ill", // 52
    "X53 ill", // 53
    "X54 ill", // 54
    "EOR zpg,X", // 55
    "LSR zpg,X", // 56
    "X57 ill", // 57
    "CLI impl", // 58
    "EOR abs,Y", // 59
    "X5A ill", // 5a
    "X5B ill", // 5b
    "X5C ill", // 5c
    "EOR abs,X", // 5d
    "LSR abs,X", // 5e
    "X5F ill", // 5f
    "RTS impl", // 60
    "ADC X,ind", // 61
    "X62 ill", // 62
    "X63 ill", // 63
    "X64 ill", // 64
    "ADC zpg", // 65
    "ROR zpg", // 66
    "X67 ill", // 67
    "PLA impl", // 68
    "ADC #", // 69
    "RORA impl", // 6a
    "X6B ill", // 6b
    "JMP ind", // 6c
    "ADC abs", // 6d
    "ROR abs", // 6e
    "X6F ill", // 6f
    "BVS rel", // 70
    "ADC ind,Y", // 71
    "X72 ill", // 72
    "X73 ill", // 73
    "X74 ill", // 74
    "ADC zpg,X", // 75
    "ROR zpg,X", // 76
    "X77 ill", // 77
    "SEI impl", // 78
    "ADC abs,Y", // 79
    "X7A ill", // 7a
    "X7B ill", // 7b
    "X7C ill", // 7c
    "ADC abs,X", // 7d
    "ROR abs,X", // 7e
    "X7F ill", // 7f
    "X80 ill", // 80
    "STA X,ind", // 81
    "X82 ill", // 82
    "X83 ill", // 83
    "STY zpg", // 84
    "STA zpg", // 85
    "STX zpg", // 86
    "X87 ill", // 87
    "DEY impl", // 88
    "X89 ill", // 89
    "TXA impl", // 8a
    "X8B ill", // 8b
    "STY abs", // 8c
    "STA abs", // 8d
    "STX abs", // 8e
    "X8F ill", // 8f
    "BCC rel", // 90
    "STA ind,Y", // 91
    "X92 ill", // 92
    "X93 ill", // 93
    "STY zpg,X", // 94
    "STA zpg,X", // 95
    "STX zpg,Y", // 96
    "X97 ill", // 97
    "TYA impl", // 98
    "STA abs,Y", // 99
    "TXS impl", // 9a
    "X9B ill", // 9b
    "X9C ill", // 9c
    "STA abs,X", // 9d
    "X9E ill", // 9e
    "X9F ill", // 9f
    "LDY #", // a0
    "LDA X,ind", // a1 LDA (zp, X)
    "LDX #", // a2
    "XA3 ill", // a3
    "LDY zpg", // a4
    "LDA zpg", // a5
    "LDX zpg", // a6
    "XA7 ill", // a7
    "TAY impl", // a8
    "LDA #", // a9
    "TAX impl", // aa
    "XAB ill", // ab
    "LDY abs", // ac
    "LDA abs", // ad
    "LDX abs", // ae
    "XAF ill", // af
    "BCS rel", // b0
    "LDA ind,Y", // b1 LDA (zp), Y
    "XB2 ill", // b2
    "XB3 ill", // b3
    "LDY zpg,X", // b4
    "LDA zpg,X", // b5
    "LDX zpg,Y", // b6
    "XB7 ill", // b7
    "CLV impl", // b8
    "LDA abs,Y", // b9
    "TSX impl", // ba
    "XBB ill", // bb
    "LDY abs,X", // bc
    "LDA abs,X", // bd
    "LDX abs,Y", // be
    "XBF ill", // bf
    "CPY #", // c0
    "CMP X,ind", // c1
    "XC2 ill", // c2
    "XC3 ill", // c3
    "CPY zpg", // c4
    "CMP zpg", // c5
    "DEC zpg", // c6
    "XC7 ill", // c7
    "INY impl", // c8
    "CMP #", // c9
    "DEX impl", // ca
    "XCB ill", // cb
    "CPY abs", // cc
    "CMP abs", // cd
    "DEC abs", // ce
    "XCF ill", // cf
    "BNE rel", // d0
    "CMP ind,Y", // d1
    "XD2 ill", // d2
    "XD3 ill", // d3
    "XD4 ill", // d4
    "CMP zpg,X", // d5
    "DEC zpg,X", // d6
    "XD7 ill", // d7
    "CLD impl", // d8
    "CMP abs,Y", // d9
    "XDA ill", // da
    "XDB ill", // db
    "XDC ill", // dc
    "CMP abs,X", // dd
    "DEC abs,X", // de
    "XDF ill", // df
    "CPX #", // e0
    "SBC X,ind", // e1
    "XE2 ill", // e2
    "XE3 ill", // e3
    "CPX zpg", // e4
    "SBC zpg", // e5
    "INC zpg", // e6
    "XE7 ill", // e7
    "INX impl", // e8
    "SBC #", // e9
    "NOP impl", // ea
    "XEB ill", // eb
    "CPX abs", // ec
    "SBC abs", // ed
    "INC abs", // ee
    "XEF ill", // ef
    "BEQ rel", // f0
    "SBC ind,Y", // f1
    "XF2 ill", // f2
    "XF3 ill", // f3
    "XF4 ill", // f4
    "SBC zpg,X", // f5
    "INC zpg,X", // f6
    "XF7 ill", // f7
    "SED impl", // f8
    "SBC abs,Y", // f9
    "XFA ill", // fa
    "XFB ill", // fb
    "XFC ill", // fc
    "SBC abs,X", // fd
    "INC abs,X", // fe
    "XFF ill", // ff
};

pub fn makeMemory() type {
    const MEMC = struct {
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

    return MEMC;
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
        const flags = if (byte == 0) Z_BIT else 0 | if (byte & 0x80 != 0) N_BIT else 0;
        cpu.P = (cpu.P & ~(Z_BIT | N_BIT)) | flags;
        return byte;
    }

    fn set_c(cpu: anytype, value: bool) void {
        if (value) {
            cpu.P |= C_BIT;
        } else {
            cpu.P &= ~C_BIT;
        }
    }

    fn shl(comptime c_in: bool, cpu: anytype, byte: u8) u8 {
        const c_out = (byte & 0x80) != 0;
        const result = byte << 1 | if (c_in and cpu.P & C_BIT) 1 else 0;
        Self.set_c(cpu, c_out);
        return Self.set_nz(cpu, result);
    }

    fn shr(comptime c_in: bool, cpu: anytype, byte: u8) u8 {
        const c_out = (byte & 0x01) != 0;
        const result = byte >> 1 | if (c_in and cpu.P & C_BIT) 0x80 else 0;
        Self.set_c(cpu, c_out);
        return Self.set_nz(cpu, result);
    }

    fn adc(cpu: anytype, lhs: u8, rhs: u8) u8 {
        _ = cpu;
        _ = lhs;
        _ = rhs;
    }

    fn sbc(cpu: anytype, lhs: u8, rhs: u8) u8 {
        return Self.adc(cpu, lhs, rhs ^ 0xff);
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
        _ = Self.sbc(cpu, cpu.A, cpu.mem.peek8(ea));
    }

    pub fn CPX(cpu: anytype, ea: u16) void {
        _ = Self.sbc(cpu, cpu.X, cpu.mem.peek8(ea));
    }

    pub fn CPY(cpu: anytype, ea: u16) void {
        _ = Self.sbc(cpu, cpu.Y, cpu.mem.peek8(ea));
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
    pub fn @"#"(cpu: anytype) u16 {
        const addr = cpu.PC;
        _ = cpu.fetch8();
        return addr;
    }

    fn zp16(cpu: anytype, zp: u8) u16 {
        const lo: u16 = @intCast(cpu.mem.peek8(zp));
        const hi: u16 = @intCast(cpu.mem.peek8(zp +% 1));
        return @as(u16, (hi << 8) | lo);
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
        const lo_addr = cpu.fetch16();
        var hi_addr: u16 = lo_addr +% 1;
        // Simulate JMP () bug
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
                self.PC = self.mem.fetch16(RESETV);
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
    const M6502 = make6502(Memory, instruction_set);
    _ = M6502;
}

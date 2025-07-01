const std = @import("std");
const constants = @import("constants.zig");

pub const Instructions = struct {
    const Self = @This();

    fn set_nz(cpu: anytype, byte: u8) u8 {
        cpu.P.Z = byte == 0;
        cpu.P.N = (byte & 0x80) != 0;
        return byte;
    }

    fn carry(comptime value: u8, cpu: anytype) u8 {
        if (cpu.P.C) {
            return value;
        } else {
            return 0x00;
        }
    }

    fn rol(cpu: anytype, byte: u8) u8 {
        const c_in = carry(0x01, cpu);
        cpu.P.C = (byte & 0x80) != 0;
        return Self.set_nz(cpu, byte << 1 | c_in);
    }

    fn ror(cpu: anytype, byte: u8) u8 {
        const c_in = carry(0x80, cpu);
        cpu.P.C = (byte & 0x01) != 0;
        return Self.set_nz(cpu, byte >> 1 | c_in);
    }

    fn shl(cpu: anytype, byte: u8) u8 {
        cpu.P.C = (byte & 0x80) != 0;
        return Self.set_nz(cpu, byte << 1);
    }

    fn shr(cpu: anytype, byte: u8) u8 {
        cpu.P.C = (byte & 0x01) != 0;
        return Self.set_nz(cpu, byte >> 1);
    }

    fn adc_binary(cpu: anytype, lhs: u8, rhs: u8) u8 {
        const c_in = carry(0x01, cpu);
        const result: u16 = @as(u16, lhs) + @as(u16, rhs) + @as(u16, c_in);
        cpu.P.C = result & 0x100 != 0;
        cpu.P.V = ((lhs ^ result) & (rhs ^ result) & 0x80) != 0;
        return Self.set_nz(cpu, @intCast(result & 0xff));
    }

    fn adc_decimal(cpu: anytype, lhs: u8, rhs: u8) u8 {
        const c_in = carry(0x01, cpu);
        const bin_res: u8 = (lhs + rhs + c_in) & 0xff;

        var dr_lo: u8 = (lhs & 0x0f) + (rhs & 0x0f) + c_in;
        var dr_hi: u8 = (lhs >> 4) + (rhs >> 4);
        if (dr_lo > 9) {
            dr_lo = (dr_lo - 10) & 0x0f;
            dr_hi += 1;
        }

        cpu.P.N = dr_hi & 0x08 != 0;
        cpu.P.Z = bin_res == 0;
        cpu.P.V = (lhs ^ rhs & 0x80 == 0) and ((lhs ^ (dr_hi << 4)) & 0x80 != 0);
        cpu.P.C = false;

        if (dr_hi > 9) {
            dr_hi -= 10;
            dr_hi &= 0x0f;
            cpu.P.C = true;
        }

        return @as(u8, (dr_hi << 4) | dr_lo);
    }

    fn sbc_decimal(cpu: anytype, lhs: u8, rhs: u8) u8 {
        const c_in = carry(0x01, cpu);
        const bin_res: u16 = (@as(u16, lhs) -% @as(u16, rhs) -% 1 +% @as(u16, c_in));

        cpu.P.N = (bin_res & 0x80) != 0;
        cpu.P.Z = (bin_res & 0xff) == 0;
        cpu.P.V = ((lhs ^ bin_res) & (rhs ^ bin_res) & 0x80) != 0;
        cpu.P.C = bin_res & 0x100 != 0;

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
        if (cpu.P.D) {
            return Self.adc_decimal(cpu, lhs, rhs);
        } else {
            return Self.adc_binary(cpu, lhs, rhs);
        }
    }

    fn sbc(cpu: anytype, lhs: u8, rhs: u8) u8 {
        if (cpu.P.D) {
            return Self.sbc_decimal(cpu, lhs, rhs);
        } else {
            return Self.adc_binary(cpu, lhs, rhs ^ 0xff);
        }
    }

    fn cmp(cpu: anytype, lhs: u8, rhs: u8) void {
        cpu.P.C = true;
        _ = Self.adc_binary(cpu, lhs, rhs ^ 0xff);
    }

    pub fn ADC(cpu: anytype, ea: u16) void {
        cpu.A = Self.adc(cpu, cpu.A, cpu.peek8(ea));
    }

    pub fn AND(cpu: anytype, ea: u16) void {
        cpu.A = Self.set_nz(cpu, cpu.A & cpu.peek8(ea));
    }

    pub fn ASL(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, Self.shl(cpu, cpu.peek8(ea)));
    }

    pub fn ASLA(cpu: anytype) void {
        cpu.A = Self.shl(cpu, cpu.A);
    }

    pub fn BCC(cpu: anytype, ea: u16) void {
        if (!cpu.P.C) cpu.PC = ea;
    }

    pub fn BCS(cpu: anytype, ea: u16) void {
        if (cpu.P.C) cpu.PC = ea;
    }

    pub fn BEQ(cpu: anytype, ea: u16) void {
        if (cpu.P.Z) cpu.PC = ea;
    }

    pub fn BIT(cpu: anytype, ea: u16) void {
        const byte = cpu.A & cpu.peek8(ea);
        cpu.P.Z = byte == 0;
        cpu.P.N = (byte & 0x80) != 0;
        cpu.P.V = (byte & 0x40 != 0);
    }

    pub fn BMI(cpu: anytype, ea: u16) void {
        if (cpu.P.N) cpu.PC = ea;
    }

    pub fn BNE(cpu: anytype, ea: u16) void {
        if (!cpu.P.Z) cpu.PC = ea;
    }

    pub fn BPL(cpu: anytype, ea: u16) void {
        if (!cpu.P.N) cpu.PC = ea;
    }

    pub fn BRK(cpu: anytype) void {
        cpu.push16(cpu.PC);
        Self.PHP(cpu);
        cpu.P.B = true;
        cpu.P.I = true;
        cpu.PC = cpu.peek16(constants.IRQV);
    }

    pub fn BVC(cpu: anytype, ea: u16) void {
        if (!cpu.P.V) cpu.PC = ea;
    }

    pub fn BVS(cpu: anytype, ea: u16) void {
        if (cpu.P.V) cpu.PC = ea;
    }

    pub fn CLC(cpu: anytype) void {
        cpu.P.C = false;
    }

    pub fn CLD(cpu: anytype) void {
        cpu.P.D = false;
    }

    pub fn CLI(cpu: anytype) void {
        cpu.P.I = false;
    }

    pub fn CLV(cpu: anytype) void {
        cpu.P.V = false;
    }

    pub fn CMP(cpu: anytype, ea: u16) void {
        Self.cmp(cpu, cpu.A, cpu.peek8(ea));
    }

    pub fn CPX(cpu: anytype, ea: u16) void {
        Self.cmp(cpu, cpu.X, cpu.peek8(ea));
    }

    pub fn CPY(cpu: anytype, ea: u16) void {
        Self.cmp(cpu, cpu.Y, cpu.peek8(ea));
    }

    pub fn DEC(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, Self.set_nz(cpu, cpu.peek8(ea) -% 1));
    }

    pub fn DEX(cpu: anytype) void {
        cpu.X = Self.set_nz(cpu, cpu.X -% 1);
    }

    pub fn DEY(cpu: anytype) void {
        cpu.Y = Self.set_nz(cpu, cpu.Y -% 1);
    }

    pub fn EOR(cpu: anytype, ea: u16) void {
        cpu.A = Self.set_nz(cpu, cpu.A ^ cpu.peek8(ea));
    }

    pub fn INC(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, Self.set_nz(cpu, cpu.peek8(ea) +% 1));
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
        cpu.A = Self.set_nz(cpu, cpu.peek8(ea));
    }

    pub fn LDX(cpu: anytype, ea: u16) void {
        cpu.X = Self.set_nz(cpu, cpu.peek8(ea));
    }

    pub fn LDY(cpu: anytype, ea: u16) void {
        cpu.Y = Self.set_nz(cpu, cpu.peek8(ea));
    }

    pub fn LSR(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, Self.shr(cpu, cpu.peek8(ea)));
    }

    pub fn LSRA(cpu: anytype) void {
        cpu.A = Self.shr(cpu, cpu.A);
    }

    pub fn NOP(cpu: anytype) void {
        _ = cpu;
    }

    pub fn ORA(cpu: anytype, ea: u16) void {
        cpu.A = Self.set_nz(cpu, cpu.A | cpu.peek8(ea));
    }

    pub fn PHA(cpu: anytype) void {
        cpu.push8(cpu.A);
    }

    pub fn PHP(cpu: anytype) void {
        cpu.P.Q = true;
        cpu.push8(@bitCast(cpu.P));
    }

    pub fn PLA(cpu: anytype) void {
        cpu.A = Self.set_nz(cpu, cpu.pop8());
    }
    pub fn PLP(cpu: anytype) void {
        cpu.P = @bitCast(cpu.pop8());
    }

    pub fn ROL(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, Self.rol(cpu, cpu.peek8(ea)));
    }

    pub fn ROLA(cpu: anytype) void {
        cpu.A = Self.rol(cpu, cpu.A);
    }

    pub fn ROR(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, Self.ror(cpu, cpu.peek8(ea)));
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
        cpu.A = Self.sbc(cpu, cpu.A, cpu.peek8(ea));
    }

    pub fn SEC(cpu: anytype) void {
        cpu.P.C = true;
    }

    pub fn SED(cpu: anytype) void {
        cpu.P.D = true;
    }

    pub fn SEI(cpu: anytype) void {
        cpu.P.I = true;
    }

    pub fn STA(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, cpu.A);
    }

    pub fn STX(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, cpu.X);
    }

    pub fn STY(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, cpu.Y);
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

const std = @import("std");
const constants = @import("constants.zig");
const ZpgRel = @import("address_modes.zig").ZpgRel;

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

    pub fn ADC(cpu: anytype, ea: u16) void {
        cpu.A = cpu.alu.adc(cpu, cpu.A, cpu.peek8(ea));
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
        const byte = cpu.peek8(ea);
        cpu.P.Z = (cpu.A & byte) == 0;
        cpu.P.N = (byte & 0x80) != 0;
        cpu.P.V = (byte & 0x40) != 0;
    }

    pub fn BITA(cpu: anytype, ea: u16) void {
        const byte = cpu.peek8(ea);
        cpu.P.Z = (cpu.A & byte) == 0;
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
        cpu.handleBRK();
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
        cpu.alu.cmp(cpu, cpu.A, cpu.peek8(ea));
    }

    pub fn CPX(cpu: anytype, ea: u16) void {
        cpu.alu.cmp(cpu, cpu.X, cpu.peek8(ea));
    }

    pub fn CPY(cpu: anytype, ea: u16) void {
        cpu.alu.cmp(cpu, cpu.Y, cpu.peek8(ea));
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
        var psr = cpu.P;
        psr.Q = true;
        psr.B = true; // Set B bit for BRK instruction
        cpu.push8(@bitCast(psr));
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
        cpu.A = cpu.alu.sbc(cpu, cpu.A, cpu.peek8(ea));
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

    // 65c02 additions
    pub fn DECA(cpu: anytype) void {
        cpu.A = Self.set_nz(cpu, cpu.A -% 1);
    }

    pub fn INCA(cpu: anytype) void {
        cpu.A = Self.set_nz(cpu, cpu.A +% 1);
    }

    pub fn PHX(cpu: anytype) void {
        cpu.push8(cpu.X);
    }

    pub fn PLX(cpu: anytype) void {
        cpu.X = Self.set_nz(cpu, cpu.pop8());
    }

    pub fn PHY(cpu: anytype) void {
        cpu.push8(cpu.Y);
    }

    pub fn PLY(cpu: anytype) void {
        cpu.Y = Self.set_nz(cpu, cpu.pop8());
    }

    pub fn STZ(cpu: anytype, ea: u16) void {
        cpu.poke8(ea, 0x00);
    }

    pub fn TRB(cpu: anytype, ea: u16) void {
        const byte = cpu.peek8(ea);
        cpu.P.Z = (byte & cpu.A) == 0;
        cpu.poke8(ea, byte & ~cpu.A);
    }

    pub fn TSB(cpu: anytype, ea: u16) void {
        const byte = cpu.peek8(ea);
        cpu.P.Z = (byte & cpu.A) == 0;
        cpu.poke8(ea, byte | cpu.A);
    }

    pub fn BRA(cpu: anytype, ea: u16) void {
        cpu.PC = ea;
    }

    fn bbr(comptime bit: u3, cpu: anytype, ea: ZpgRel) void {
        const zp, const dest = ea;
        if (cpu.peek8(zp) & (1 << bit) == 0)
            cpu.PC = dest;
    }

    fn bbs(comptime bit: u3, cpu: anytype, ea: ZpgRel) void {
        const zp, const dest = ea;
        if (cpu.peek8(zp) & (1 << bit) != 0)
            cpu.PC = dest;
    }

    pub fn BBR0(cpu: anytype, ea: ZpgRel) void {
        Self.bbr(0, cpu, ea);
    }
    pub fn BBR1(cpu: anytype, ea: ZpgRel) void {
        Self.bbr(1, cpu, ea);
    }
    pub fn BBR2(cpu: anytype, ea: ZpgRel) void {
        Self.bbr(2, cpu, ea);
    }
    pub fn BBR3(cpu: anytype, ea: ZpgRel) void {
        Self.bbr(3, cpu, ea);
    }
    pub fn BBR4(cpu: anytype, ea: ZpgRel) void {
        Self.bbr(4, cpu, ea);
    }
    pub fn BBR5(cpu: anytype, ea: ZpgRel) void {
        Self.bbr(5, cpu, ea);
    }
    pub fn BBR6(cpu: anytype, ea: ZpgRel) void {
        Self.bbr(6, cpu, ea);
    }
    pub fn BBR7(cpu: anytype, ea: ZpgRel) void {
        Self.bbr(7, cpu, ea);
    }

    pub fn BBS0(cpu: anytype, ea: ZpgRel) void {
        Self.bbs(0, cpu, ea);
    }
    pub fn BBS1(cpu: anytype, ea: ZpgRel) void {
        Self.bbs(1, cpu, ea);
    }
    pub fn BBS2(cpu: anytype, ea: ZpgRel) void {
        Self.bbs(2, cpu, ea);
    }
    pub fn BBS3(cpu: anytype, ea: ZpgRel) void {
        Self.bbs(3, cpu, ea);
    }
    pub fn BBS4(cpu: anytype, ea: ZpgRel) void {
        Self.bbs(4, cpu, ea);
    }
    pub fn BBS5(cpu: anytype, ea: ZpgRel) void {
        Self.bbs(5, cpu, ea);
    }
    pub fn BBS6(cpu: anytype, ea: ZpgRel) void {
        Self.bbs(6, cpu, ea);
    }
    pub fn BBS7(cpu: anytype, ea: ZpgRel) void {
        Self.bbs(7, cpu, ea);
    }

    fn rmb(comptime bit: u3, cpu: anytype, ea: u16) void {
        const byte = cpu.peek8(ea);
        const mask: u8 = 1 << bit;
        cpu.poke8(ea, byte & ~mask);
    }

    fn smb(comptime bit: u3, cpu: anytype, ea: u16) void {
        const byte = cpu.peek8(ea);
        cpu.poke8(ea, byte | (1 << bit));
    }

    pub fn RMB0(cpu: anytype, ea: u16) void {
        Self.rmb(0, cpu, ea);
    }
    pub fn RMB1(cpu: anytype, ea: u16) void {
        Self.rmb(1, cpu, ea);
    }
    pub fn RMB2(cpu: anytype, ea: u16) void {
        Self.rmb(2, cpu, ea);
    }
    pub fn RMB3(cpu: anytype, ea: u16) void {
        Self.rmb(3, cpu, ea);
    }
    pub fn RMB4(cpu: anytype, ea: u16) void {
        Self.rmb(4, cpu, ea);
    }
    pub fn RMB5(cpu: anytype, ea: u16) void {
        Self.rmb(5, cpu, ea);
    }
    pub fn RMB6(cpu: anytype, ea: u16) void {
        Self.rmb(6, cpu, ea);
    }
    pub fn RMB7(cpu: anytype, ea: u16) void {
        Self.rmb(7, cpu, ea);
    }

    pub fn SMB0(cpu: anytype, ea: u16) void {
        Self.smb(0, cpu, ea);
    }
    pub fn SMB1(cpu: anytype, ea: u16) void {
        Self.smb(1, cpu, ea);
    }
    pub fn SMB2(cpu: anytype, ea: u16) void {
        Self.smb(2, cpu, ea);
    }
    pub fn SMB3(cpu: anytype, ea: u16) void {
        Self.smb(3, cpu, ea);
    }
    pub fn SMB4(cpu: anytype, ea: u16) void {
        Self.smb(4, cpu, ea);
    }
    pub fn SMB5(cpu: anytype, ea: u16) void {
        Self.smb(5, cpu, ea);
    }
    pub fn SMB6(cpu: anytype, ea: u16) void {
        Self.smb(6, cpu, ea);
    }
    pub fn SMB7(cpu: anytype, ea: u16) void {
        Self.smb(7, cpu, ea);
    }

    pub fn STP(cpu: anytype) void {
        cpu.stop();
    }

    pub fn WAI(cpu: anytype) void {
        cpu.sleep();
        switch (cpu.getInterruptState()) {
            .None => cpu.PC -%= 1, // Loop back to wait for interrupt
            else => {},
        }
    }
};

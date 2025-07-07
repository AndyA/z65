pub const AddressModes = struct {
    const Self = @This();
    fn zp16(cpu: anytype, zp: u8) u16 {
        const lo: u16 = cpu.peek8(zp);
        const hi: u16 = cpu.peek8(zp +% 1);
        return @as(u16, (hi << 8) | lo);
    }

    pub fn @"#"(cpu: anytype) u16 {
        const addr = cpu.PC;
        _ = cpu.fetch8();
        return addr;
    }

    pub fn @"(zpg, X)"(cpu: anytype) u16 {
        const zp = cpu.fetch8();
        return Self.zp16(cpu, zp +% cpu.X);
    }

    pub fn abs(cpu: anytype) u16 {
        return cpu.fetch16();
    }

    pub fn @"abs, X"(cpu: anytype) u16 {
        return cpu.fetch16() +% cpu.X;
    }

    pub fn @"abs, Y"(cpu: anytype) u16 {
        return cpu.fetch16() +% cpu.Y;
    }

    pub fn @"(abs)"(cpu: anytype) u16 {
        const addr = cpu.fetch16();
        return cpu.peek16(addr);
    }

    pub fn @"(abs)*"(cpu: anytype) u16 {
        // Simulate JMP () bug
        const lo_addr = cpu.fetch16();
        var hi_addr: u16 = lo_addr +% 1;
        if (hi_addr & 0x00FF == 0x0000) {
            hi_addr -= 0x0100;
        }
        const lo: u16 = cpu.peek8(lo_addr);
        const hi: u16 = cpu.peek8(hi_addr);
        return @as(u16, (hi << 8) | lo);
    }

    pub fn @"(zpg), Y"(cpu: anytype) u16 {
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

    pub fn @"zpg, X"(cpu: anytype) u16 {
        return @intCast(cpu.fetch8() +% cpu.X);
    }

    pub fn @"zpg, Y"(cpu: anytype) u16 {
        return @intCast(cpu.fetch8() +% cpu.Y);
    }
};

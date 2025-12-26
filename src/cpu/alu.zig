const std = @import("std");

fn carry(comptime value: u8, cpu: anytype) u8 {
    if (cpu.P.C) {
        return value;
    } else {
        return 0x00;
    }
}

fn set_nz(cpu: anytype, byte: u8) u8 {
    cpu.P.Z = byte == 0;
    cpu.P.N = (byte & 0x80) != 0;
    return byte;
}

fn adc_binary(cpu: anytype, lhs: u8, rhs: u8) u8 {
    const c_in = carry(0x01, cpu);
    const result: u16 = @as(u16, lhs) + @as(u16, rhs) + @as(u16, c_in);
    cpu.P.C = result & 0x100 != 0;
    cpu.P.V = ((lhs ^ result) & (rhs ^ result) & 0x80) != 0;
    return set_nz(cpu, @intCast(result & 0xff));
}

pub const ALU6502 = struct {
    const Self = @This();

    fn adc_decimal(cpu: anytype, lhs: u8, rhs: u8) u8 {
        const c_in = carry(0x01, cpu);
        const bin_res: u16 = (@as(u16, lhs) + @as(u16, rhs) + @as(u16, c_in)) & 0xff;

        var dr_lo: u8 = (lhs & 0x0f) + (rhs & 0x0f) + c_in;
        var dr_hi: u8 = (lhs >> 4) + (rhs >> 4);
        if (dr_lo > 9) {
            dr_lo -= 10;
            dr_hi += 1;
        }

        cpu.P.N = dr_hi & 0x08 != 0;
        cpu.P.Z = (bin_res & 0xff) == 0;
        cpu.P.V = (lhs ^ rhs & 0x80 == 0) and ((lhs ^ (dr_hi << 4)) & 0x80 != 0);
        cpu.P.C = false;

        if (dr_hi > 9) {
            dr_hi -%= 10;
            cpu.P.C = true;
        }

        return @intCast((dr_lo & 0x0f) | (dr_hi & 0x0f) << 4);
    }

    fn sbc_decimal(cpu: anytype, lh: u8, rh: u8) u8 {
        const c_in: u16 = 1 - carry(1, cpu);
        const lhs = @as(u16, lh);
        const rhs = @as(u16, rh);
        var dr_lo = (lhs & 0x0f) -% (rhs & 0x0f) -% c_in;
        var dr_hi = (lhs >> 4) -% (rhs >> 4);

        if (dr_lo & 0x10 != 0) {
            dr_lo -= 6;
            dr_hi -%= 1;
        }

        const bin_res: u16 = lhs -% rhs -% c_in;
        cpu.P.N = (bin_res & 0x80) != 0;
        cpu.P.Z = (bin_res & 0xff) == 0;
        cpu.P.V = (lhs ^ rhs & 0x80 != 0) and ((lhs ^ (dr_hi << 4)) & 0x80 != 0);
        cpu.P.C = (bin_res & 0x100) == 0;

        if (dr_hi & 0x10 != 0) {
            dr_hi -= 6;
        }

        return @intCast((dr_lo & 0x0f) | (dr_hi & 0x0f) << 4);
    }

    pub fn adc(self: Self, cpu: anytype, lhs: u8, rhs: u8) u8 {
        _ = self;
        if (cpu.P.D) {
            @branchHint(.unlikely);
            return adc_decimal(cpu, lhs, rhs);
        } else {
            return adc_binary(cpu, lhs, rhs);
        }
    }

    pub fn sbc(self: Self, cpu: anytype, lhs: u8, rhs: u8) u8 {
        _ = self;
        if (cpu.P.D) {
            @branchHint(.unlikely);
            return sbc_decimal(cpu, lhs, rhs);
        } else {
            return adc_binary(cpu, lhs, rhs ^ 0xff);
        }
    }

    pub fn cmp(self: Self, cpu: anytype, lhs: u8, rhs: u8) void {
        _ = self;
        const result: u16 = @as(u16, lhs) + @as(u16, rhs ^ 0xff) + 1;
        cpu.P.C = result & 0x100 != 0;
        _ = set_nz(cpu, @intCast(result & 0xff));
    }
};

pub const ALU65C02 = struct {
    const Self = @This();

    fn adc_decimal(cpu: anytype, lhs: u8, rhs: u8) u8 {
        const c_in = carry(0x01, cpu);

        var dr_lo: u8 = (lhs & 0x0f) + (rhs & 0x0f) + c_in;
        var dr_hi: u8 = (lhs >> 4) + (rhs >> 4);
        if (dr_lo > 9) {
            dr_lo -= 10;
            dr_hi += 1;
        }

        cpu.P.C = false;

        if (dr_hi > 9) {
            dr_hi -%= 10;
            cpu.P.C = true;
        }
        const result: u8 = @intCast((dr_lo & 0x0f) | (dr_hi & 0x0f) << 4);
        return set_nz(cpu, result);
    }

    fn sbc_decimal(cpu: anytype, lh: u8, rh: u8) u8 {
        const c_in: u16 = 1 - carry(1, cpu);
        const lhs = @as(u16, lh);
        const rhs = @as(u16, rh);
        var dr_lo = (lhs & 0x0f) -% (rhs & 0x0f) -% c_in;
        var dr_hi = (lhs >> 4) -% (rhs >> 4);

        if (dr_lo & 0x10 != 0) {
            dr_lo -= 6;
            dr_hi -%= 1;
        }

        const bin_res: u16 = lhs -% rhs -% c_in;
        cpu.P.C = (bin_res & 0x100) == 0;

        if (dr_hi & 0x10 != 0) {
            dr_hi -= 6;
        }

        const result: u8 = @intCast((dr_lo & 0x0f) | (dr_hi & 0x0f) << 4);
        return set_nz(cpu, result);
    }

    pub fn adc(self: Self, cpu: anytype, lhs: u8, rhs: u8) u8 {
        _ = self;
        if (cpu.P.D) {
            @branchHint(.unlikely);
            return adc_decimal(cpu, lhs, rhs);
        } else {
            return adc_binary(cpu, lhs, rhs);
        }
    }

    pub fn sbc(self: Self, cpu: anytype, lhs: u8, rhs: u8) u8 {
        _ = self;
        if (cpu.P.D) {
            @branchHint(.unlikely);
            return sbc_decimal(cpu, lhs, rhs);
        } else {
            return adc_binary(cpu, lhs, rhs ^ 0xff);
        }
    }

    pub fn cmp(self: Self, cpu: anytype, lhs: u8, rhs: u8) void {
        _ = self;
        const result: u16 = @as(u16, lhs) + @as(u16, rhs ^ 0xff) + 1;
        cpu.P.C = result & 0x100 != 0;
        _ = set_nz(cpu, @intCast(result & 0xff));
    }
};

fn loadTestData(comptime name: []const u8, comptime kind: []const u8) []const u8 {
    const base = name ++ "/W." ++ kind;
    const data = @embedFile(base ++ "0") ++
        @embedFile(base ++ "1") ++
        @embedFile(base ++ "2") ++
        @embedFile(base ++ "3") ++
        @embedFile(base ++ "4") ++
        @embedFile(base ++ "5") ++
        @embedFile(base ++ "6") ++
        @embedFile(base ++ "7");

    return data;
}

const TestVector = struct { res: []const u8, psr: []const u8 };

fn loadTestVector(comptime name: []const u8) TestVector {
    const res = loadTestData(name, "RES");
    const psr = loadTestData(name, "PST");
    return .{ .res = res, .psr = psr };
}

const Op = enum(u8) { ADC, SBC };

fn test6502Decimal(vector: TestVector, op: Op, carry_in: bool) !void {
    const expect = std.testing.expect;

    const PSR = @import("status_reg.zig").PSR;
    const TestCPU = struct {
        P: PSR = PSR{},
    };

    try expect(vector.res.len == 65536);
    var res_error: usize = 0;
    var psr_error: usize = 0;
    var printing = true;
    const alu = ALU6502{};
    for (0..256) |rhs| {
        for (0..256) |lhs| {
            var cpu = TestCPU{};
            cpu.P.D = true;
            cpu.P.C = carry_in;
            cpu.P.B = true;
            cpu.P.Q = true; // Q bit is always set to 1
            const res_got = switch (op) {
                .ADC => alu.adc(&cpu, @intCast(lhs), @intCast(rhs)),
                .SBC => alu.sbc(&cpu, @intCast(lhs), @intCast(rhs)),
            };
            cpu.P.D = false;
            const psr_got = cpu.P.value();
            const slot = (rhs << 8) | lhs;

            if (res_got != vector.res[slot])
                res_error += 1;

            if (psr_got != vector.psr[slot])
                psr_error += 1;

            if (printing) {
                if (res_got != vector.res[slot] or psr_got != vector.psr[slot]) {
                    std.debug.print("Bad result at {x:0>2}, {x:0>2}", .{ lhs, rhs });
                    if (res_got != vector.res[slot]) {
                        std.debug.print(" RES: {x:0>2} != {x:0>2}", .{ res_got, vector.res[slot] });
                    }

                    if (psr_got != vector.psr[slot]) {
                        const p_got: PSR = @bitCast(psr_got);
                        const p_want: PSR = @bitCast(vector.psr[slot]);
                        std.debug.print(" PSR: {f} != {f}", .{ p_got, p_want });
                    }
                    std.debug.print("\n", .{});
                }
                if (res_error + psr_error > 100) {
                    std.debug.print("Too many errors\n", .{});
                    printing = false;
                }
            }
        }
    }

    if (res_error > 0 or psr_error > 0) {
        std.debug.print("{d} RES errors, {d} PSR errors\n", .{ res_error, psr_error });
    }

    try expect(res_error == 0);
    try expect(psr_error == 0);
}

test "decimal adc_cc" {
    const ADC_CC = loadTestVector("test/data/decimal/adc_cc");
    try test6502Decimal(ADC_CC, .ADC, false);
}

test "decimal adc_cs" {
    const ADC_CS = loadTestVector("test/data/decimal/adc_cs");
    try test6502Decimal(ADC_CS, .ADC, true);
}

test "decimal sbc_cc" {
    const SBC_CC = loadTestVector("test/data/decimal/sbc_cc");
    try test6502Decimal(SBC_CC, .SBC, false);
}

test "decimal sbc_cs" {
    const SBC_CS = loadTestVector("test/data/decimal/sbc_cs");
    try test6502Decimal(SBC_CS, .SBC, true);
}

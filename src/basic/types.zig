const std = @import("std");
const serde = @import("../tools/serde.zig");

pub const BasicFPError = error{TooBig};

pub fn BasicFP(comptime T: type) type {
    return packed struct {
        const Self = @This();
        const Serde = serde.serdeBigEndian(Self);
        const zero = Self{ .exp = 0, .mant = 0 };
        exp: u8,
        mant: u32,

        const SM = packed struct {
            mag: u31,
            negative: bool,
        };

        pub fn initFromMemory(mem: anytype, addr: u16) Self {
            return Serde.read(mem, addr);
        }

        pub fn initFromValue(value: T) BasicFPError!Self {
            const negative = value < 0;
            const v = @abs(value);
            if (v == 0) return zero;
            const exp = @floor(@log2(v)) + 129;
            if (exp < 1) return zero;
            if (exp > 255) return BasicFPError.TooBig;
            const mant = v / @exp2(exp - 128 - 32);
            const u_mant: u32 = @intFromFloat(@floor(mant));
            const u_exp: u8 = @intFromFloat(exp);
            var sm: SM = @bitCast(u_mant);
            sm.negative = negative;
            // std.debug.print("u_mant: {x:0>8}, exp: {x:0>2}\n", .{ u_mant, u_exp });
            return Self{ .exp = u_exp, .mant = @bitCast(sm) };
        }

        pub fn write(self: Self, mem: anytype, addr: u16) void {
            Serde.write(mem, addr, self);
        }

        pub fn getValue(self: Self) T {
            if (self.exp == 0 and self.mant == 0)
                return 0;
            const sm: SM = @bitCast(self.mant);
            const mant: u32 = 0x80000000 | @as(u32, sm.mag);
            const f_mant: T = @floatFromInt(mant);
            const f_exp: T = @floatFromInt(self.exp);
            const mag: T = f_mant * @exp2(f_exp - 128 - 32);
            return if (sm.negative) -mag else mag;
        }
    };
}

const TestCase = struct {
    exp: u8,
    mant: u32,
    value: f64,
};

fn TC(exp: u8, mant: u32, value: f64) TestCase {
    return TestCase{ .exp = exp, .mant = mant, .value = value };
}

const test_cases = [_]TestCase{
    TC(0x00, 0x00000000, 0),
    TC(0x81, 0x00000000, 1),
    TC(0x82, 0x00000000, 2),
    TC(0x82, 0x40000000, 3),
    TC(0x83, 0x00000000, 4),
    TC(0x83, 0x20000000, 5),
    TC(0x83, 0x40000000, 6),
    TC(0x83, 0x60000000, 7),
    TC(0x84, 0x00000000, 8),
    TC(0x84, 0x10000000, 9),
    TC(0x84, 0x20000000, 10),
    TC(0x84, 0x30000000, 11),
    TC(0x84, 0x40000000, 12),
    TC(0x84, 0x50000000, 13),
    TC(0x84, 0x60000000, 14),
    TC(0x84, 0x70000000, 15),
    TC(0x85, 0x00000000, 16),

    // &12345678
    TC(0x9d, 0x11a2b3c0, 305419896),
    // -&12345678
    TC(0x9d, 0x91a2b3c0, -305419896),
    // &1234
    TC(0x8d, 0x11a00000, 4660),
    // PI
    TC(0x82, 0x490fdaa2, 3.141592653),
    // PI + 0.0000001
    TC(0x82, 0x490fdb0d, 3.141592753),
    TC(0x00, 0x00000000, 0),
    // &01020304
    TC(0x99, 0x01018200, 16909060),
    // -&01020304
    TC(0x99, 0x81018200, -16909060),
    // &8000001
    TC(0x9c, 0x00000010, 134217729),
    // -&8000001
    TC(0x9c, 0x80000010, -134217729),
    // &4000001
    TC(0x9b, 0x00000020, 67108865),
    // -&4000001
    TC(0x9b, 0x80000020, -67108865),

    TC(0x81, 0x7fffac1d, 1.99999),
    TC(0x82, 0x00000000, 2),

    TC(0x80, 0x00000000, 0.5),
    TC(0x02, 0x00000000, 5.877471754e-39),
    TC(0x01, 0x00000000, 2.938735877e-39),

    TC(0x81, 0x80000000, -1),
    TC(0x80, 0x80000000, -0.5),

    TC(0x81, 0x00000000, 1),
    TC(0x82, 0x00000000, 2),

    TC(0xfe, 0x00000000, 4.253529587e+37),
    TC(0xff, 0x00000000, 8.507059173e+37),

    // Some random values
    TC(0x7f, 0x2ee013a4, 0.3415533197),
    TC(0x80, 0x4bcf017e, 0.7961274083),
    TC(0x80, 0x5a5dfca3, 0.8529966257),
    TC(0x80, 0x2f8f2314, 0.6857778477),
    TC(0x80, 0x7934eb32, 0.9734637258),
    TC(0x80, 0x5f083a2a, 0.8712192872),
    TC(0x7e, 0x5bde40d4, 0.2147150163),
    TC(0x80, 0x4012bb95, 0.750285839),
    TC(0x80, 0x5f86f1fb, 0.8731528509),
    TC(0x7e, 0x58d65594, 0.2117551204),
    TC(0x80, 0x02f499e1, 0.5115448164),
    TC(0x80, 0x39d484ef, 0.7258990367),
    TC(0x80, 0x74f9893a, 0.9569326178),
    TC(0x80, 0x57bcdb02, 0.8427254562),
    TC(0x80, 0x41a5a0ba, 0.7564335302),
    TC(0x80, 0x104f0cd7, 0.5637062096),
    TC(0x7e, 0x7c95fcbc, 0.2466659059),
};

fn adjustedDiff(a: f64, b: f64) f64 {
    const min = @min(a, b);
    const diff = @abs(a - b);
    return @abs(if (min == 0) diff else diff / min);
}

const MAX_DIFF: f64 = 1 / std.math.pow(f64, 2, 31);

pub const BasicFP64 = BasicFP(f64);

test ".getValue" {
    for (test_cases) |tc| {
        const fp = BasicFP64{ .exp = tc.exp, .mant = tc.mant };
        const value = fp.getValue();
        const diff = adjustedDiff(tc.value, value);
        if (diff > MAX_DIFF) {
            std.debug.print("exp: {x:0>2} mant: {x:0>8} fp: {d}, got: {d}, diff: {d}\n", .{
                tc.exp,
                tc.mant,
                tc.value,
                value,
                diff,
            });
        }
        try std.testing.expect(diff <= MAX_DIFF);
    }
}

test ".initFromValue" {
    for (test_cases) |tc| {
        const fp = try BasicFP64.initFromValue(tc.value);
        const value = fp.getValue();
        const diff = adjustedDiff(tc.value, value);
        if (diff > MAX_DIFF) {
            std.debug.print("tc.exp: {x:0>2} fp.ext {x:0>2} tc.mant: {x:0>8}" ++
                " fp.mant: {x:0>8} value: {d}, diff: {d}\n", .{
                tc.exp,   fp.exp,
                tc.mant,  fp.mant,
                tc.value, diff,
            });
        }
        try std.testing.expect(diff <= MAX_DIFF);
    }
}

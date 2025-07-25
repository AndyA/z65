const std = @import("std");
const serde = @import("../tools/serde.zig");

pub const BasicFP = packed struct {
    const Self = @This();
    const Serde = serde.serdeBigEndian(Self);
    exp: u8,
    mant: u32,

    const SM = packed struct {
        mag: u31,
        negative: bool,
    };

    pub fn initFromMemory(mem: anytype, addr: u16) Self {
        return Serde.read(mem, addr);
    }

    pub fn write(self: Self, mem: anytype, addr: u16) void {
        Serde.write(mem, addr, self);
    }

    pub fn value(self: Self) f64 {
        if (self.exp == 0 and self.mant == 0)
            return 0;
        const sm: SM = @bitCast(self.mant);
        const mant: u32 = 0x80000000 | @as(u32, sm.mag);
        const f_mant: f64 = @floatFromInt(mant);
        const f_exp: f64 = @floatFromInt(self.exp);
        const mag: f64 = f_mant * std.math.pow(f64, 2, f_exp - 128 - 32);
        return if (sm.negative) -mag else mag;
    }
};

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
    TC(0x80, 0x00000000, 0.5),
    TC(0x02, 0x00000000, 5.877471754e-39),
    TC(0x01, 0x00000000, 2.938735877e-39),

    TC(0x81, 0x80000000, -1),
    TC(0x80, 0x80000000, -0.5),
    TC(0x01, 0x80000000, -2.938735877e-39),
    TC(0x00, 0x80000000, -1.469367939e-39),

    TC(0x81, 0x00000000, 1),
    TC(0x82, 0x00000000, 2),

    TC(0xfe, 0x00000000, 4.253529587e+37),
    TC(0xff, 0x00000000, 8.507059173e+37),
};

fn adjustedDiff(a: f64, b: f64) f64 {
    const min = @min(a, b);
    const diff = @abs(a - b);
    return @abs(if (min == 0) diff else diff / min);
}

const MAX_DELTA: f64 = 1 / std.math.pow(f64, 2, 31);

test BasicFP {
    for (test_cases) |tc| {
        const fp = BasicFP{ .exp = tc.exp, .mant = tc.mant };
        const value = fp.value();
        const diff = adjustedDiff(tc.value, value);
        if (diff > MAX_DELTA) {
            std.debug.print("exp: {x:0>2} mant: {x:0>8} fp: {d}, got: {d}, diff: {d}\n", .{
                tc.exp,
                tc.mant,
                tc.value,
                value,
                diff,
            });
        }
        try std.testing.expect(diff <= MAX_DELTA);
    }
}

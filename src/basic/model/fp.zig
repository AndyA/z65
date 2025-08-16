const std = @import("std");
const serde = @import("../../tools/serde.zig");

pub const BasicFPError = error{TooBig};

// String
//    word value -> pointer to value, null means empty string
// String value
//    byte alloc -> allocated length
//    byte len   -> used length
//    byte* str  -> chars
// Array
//    byte dimskip -> offset of data
//    word* dim    -> dimensions
//    byte* data   -> data

pub fn BasicFP(comptime T: type) type {
    return struct {
        const Self = @This();
        const Serde = serde.serdeBigEndian(Self);
        const zero = .{ .exp = 0, .mant = 0 };

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
            const u_mant: u32 = @intFromFloat(@floor(v / @exp2(exp - 128 - 32)));
            const u_exp: u8 = @intFromFloat(exp);
            var sm: SM = @bitCast(u_mant);
            sm.negative = negative;
            return Self{ .exp = u_exp, .mant = @bitCast(sm) };
        }

        pub fn write(self: Self, mem: anytype, addr: u16) void {
            Serde.write(mem, addr, self);
        }

        pub fn getValue(self: Self) T {
            if (self.exp == 0) return 0;
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
    TC(0x81, 0x7fffffeb, 1.99999999), // 1.99999999
    TC(0x82, 0x00000000, 2), // 2
    TC(0x82, 0x0000000b, 2.00000001), // 2.00000001
    TC(0x82, 0x490fdaa2, 3.141592653), // PI
    TC(0x82, 0x490fdaad, 3.141592664), // PI + 0.00000001
    TC(0x82, 0x490fda97, 3.141592643), // PI - 0.00000001
    TC(0xfc, 0x14898f92, 1.234e+37), // 1.234E37
    TC(0x06, 0x27f69fd4, 1.234e-37), // 1.234E-37
    TC(0x80, 0x00000000, 0.5), // 0.5
    TC(0x81, 0x00000000, 1), // 1
    TC(0x82, 0x00000000, 2), // 2
    TC(0x80, 0x80000000, -0.5), // -0.5
    TC(0x81, 0x80000000, -1), // -1
    TC(0x82, 0x80000000, -2), // -2
    TC(0xa2, 0x1502f900, 1e+10), // 10 ^ 10
    TC(0x8b, 0x00000000, 1024), // 2 ^ 10
    TC(0x81, 0x00000000, 1), // 1
    TC(0x82, 0x00000000, 2), // 2
    TC(0x82, 0x40000000, 3), // 3
    TC(0x83, 0x00000000, 4), // 4
    TC(0x83, 0x20000000, 5), // 5
    TC(0x83, 0x40000000, 6), // 6
    TC(0x83, 0x60000000, 7), // 7
    TC(0x84, 0x00000000, 8), // 8
    TC(0x84, 0x10000000, 9), // 9
    TC(0x84, 0x20000000, 10), // 10
    TC(0x84, 0x30000000, 11), // 11
    TC(0x84, 0x40000000, 12), // 12
    TC(0x84, 0x50000000, 13), // 13
    TC(0x84, 0x60000000, 14), // 14
    TC(0x84, 0x70000000, 15), // 15
    TC(0x85, 0x00000000, 16), // 16
    TC(0x85, 0x08000000, 17), // 17
    TC(0x81, 0x80000000, -1), // -1
    TC(0x82, 0x80000000, -2), // -2
    TC(0x82, 0xc0000000, -3), // -3
    TC(0x83, 0x80000000, -4), // -4
    TC(0x83, 0xa0000000, -5), // -5
    TC(0x83, 0xc0000000, -6), // -6
    TC(0x83, 0xe0000000, -7), // -7
    TC(0x84, 0x80000000, -8), // -8
    TC(0x84, 0x90000000, -9), // -9
    TC(0x84, 0xa0000000, -10), // -10
    TC(0x84, 0xb0000000, -11), // -11
    TC(0x84, 0xc0000000, -12), // -12
    TC(0x84, 0xd0000000, -13), // -13
    TC(0x84, 0xe0000000, -14), // -14
    TC(0x84, 0xf0000000, -15), // -15
    TC(0x85, 0x80000000, -16), // -16
    TC(0x85, 0x88000000, -17), // -17
    TC(0x00, 0x00000000, 0), // 0

    // Some random values
    TC(0x9f, 0xdd8e0594, -1858536138), // -1858536138
    TC(0x62, 0x93e674ef, -5.380578723e-10), // 1 / -1858536138
    TC(0x9f, 0x0e9e35de, 1196366575), // 1196366575
    TC(0x62, 0x65c2b6f3, 8.358642084e-10), // 1 / 1196366575
    TC(0x9e, 0xb7da3ea4, -771133353), // -771133353
    TC(0x63, 0xb23ad50a, -1.296792567e-9), // 1 / -771133353
    TC(0x9f, 0x7c039f96, 2114047947), // 2114047947
    TC(0x62, 0x020641e7, 4.730261684e-10), // 1 / 2114047947
    TC(0x9f, 0xb807444c, -1543741990), // -1543741990
    TC(0x62, 0xb20f3a8c, -6.477766405e-10), // 1 / -1543741990
    TC(0x9d, 0x211c7d78, 337874863), // 337874863
    TC(0x64, 0x4b632a17, 2.959675636e-9), // 1 / 337874863
    TC(0x9e, 0x4bacd3e4, 854275321), // 854275321
    TC(0x63, 0x20e2388e, 1.170582803e-9), // 1 / 854275321
    TC(0x9e, 0x28e8237c, 708446431), // 708446431
    TC(0x63, 0x42001fff, 1.411539329e-9), // 1 / 708446431
    TC(0x9e, 0x5643dcd8, 898692918), // 898692918
    TC(0x63, 0x18ee9b10, 1.11272714e-9), // 1 / 898692918
    TC(0x9f, 0xd489da80, -1782902080), // -1782902080
    TC(0x62, 0x9a2ca743, -5.608832988e-10), // 1 / -1782902080
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
                tc.exp, tc.mant, tc.value, value, diff,
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
                tc.exp, fp.exp, tc.mant, fp.mant, tc.value, diff,
            });
        }
        try std.testing.expect(diff <= MAX_DIFF);
    }
}

test "round trip random" {
    var r = std.Random.Xoroshiro128.init(0);
    const rr = r.random();

    for (1..100) |_| {
        const exp = rr.int(u8);
        const mant = if (exp == 0) 0 else rr.int(u32);
        const want = BasicFP64{ .exp = exp, .mant = mant };
        const got = try BasicFP64.initFromValue(want.getValue());
        try std.testing.expectEqual(want.exp, got.exp);
        try std.testing.expectEqual(want.mant, got.mant);
    }
}

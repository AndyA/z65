const std = @import("std");
const expect = std.testing.expect;

pub const PSR = packed struct {
    C: bool = false, // Carry
    Z: bool = false, // Zero
    I: bool = false, // Interrupt Disable
    D: bool = false, // Decimal Mode
    B: bool = false, // Break Command
    Q: bool = true, // Always set to 1
    V: bool = false, // Overflow
    N: bool = false, // Negative
    const Self = @This();

    pub fn value(self: Self) u8 {
        return @bitCast(self);
    }

    pub fn set(self: *Self, byte: u8) void {
        self.* = @bitCast(byte);
        self.Q = true; // Q bit is always set to 1
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        var buf: [8]u8 = undefined;
        const flags = self.value();

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

        try writer.print("{s}", .{buf});
    }
};

test "PSR" {
    try expect(@sizeOf(PSR) == 1);
    try expect(@bitSizeOf(PSR) == 8);
    var psr1 = PSR{};
    psr1.C = true;
    psr1.Z = true;
    try expect(psr1.value() == 0b0010_0011); // C and Z bits set
    psr1.set(0b1111_1111);
    try expect(psr1.value() == 0b1111_1111); // All bits set
}

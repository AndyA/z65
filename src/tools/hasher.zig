const std = @import("std");

pub fn hashBytes(text: []const u8) u256 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(text);
    return @bitCast(h.finalResult());
}

const std = @import("std");

pub fn hashBytes(text: []const u8) u256 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(text);
    return @bitCast(h.finalResult());
}

pub fn hexDump(mem: []const u8, offset: u16) void {
    var pos: usize = 0;
    while (pos < mem.len) : (pos += 16) {
        var avail = @min(16, mem.len - pos);
        const bytes = mem[pos .. pos + avail];
        std.debug.print("{x:0>4} |", .{pos +% offset});
        for (bytes) |byte|
            std.debug.print(" {x:0>2}", .{byte});
        while (avail < 16) : (avail += 1)
            std.debug.print("   ", .{});
        std.debug.print(" | ", .{});
        for (bytes) |byte| {
            const rep = if (std.ascii.isPrint(byte)) byte else '.';
            std.debug.print("{c}", .{rep});
        }
        std.debug.print("\n", .{});
    }
}

pub fn peek16(bytes: []const u8, addr: u16) u16 {
    if (addr + 1 >= bytes.len) @panic("Out of range");
    return @as(u16, bytes[addr]) | (@as(u16, bytes[addr + 1]) << 8);
}

pub fn peek16be(bytes: []const u8, addr: u16) u16 {
    if (addr + 1 >= bytes.len) @panic("Out of range");
    return @as(u16, bytes[addr + 1]) | (@as(u16, bytes[addr]) << 8);
}

pub fn poke16(bytes: []u8, addr: u16, value: u16) void {
    if (addr + 1 >= bytes.len) @panic("Out of range");
    bytes[addr] = @intCast(value & 0x00FF);
    bytes[addr + 1] = @intCast((value >> 8) & 0x00FF);
}

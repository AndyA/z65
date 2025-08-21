const std = @import("std");

pub fn setXY(cpu: anytype, xy: u16) void {
    cpu.X = @intCast(xy & 0xff);
    cpu.Y = @intCast(xy >> 8);
}

pub fn getXY(cpu: anytype) u16 {
    return @as(u16, cpu.Y) << 8 | @as(u16, cpu.X);
}

pub fn pokeBytes(mem: anytype, addr: u16, bytes: []const u8) void {
    for (bytes, 0..) |byte, i| {
        const offset: u16 = @intCast(i);
        mem.poke8(addr + offset, byte);
    }
}

pub fn peekBytes(mem: anytype, addr: u16, bytes: []u8) void {
    for (0..bytes.len) |i| {
        const offset: u16 = @intCast(i);
        bytes[i] = mem.peek8(addr + offset);
    }
}

pub fn peekBytesAlloc(alloc: std.mem.Allocator, mem: anytype, addr: u16, size: usize) ![]u8 {
    const buf = try alloc.alloc(u8, size);
    errdefer alloc.free(buf);
    peekBytes(mem, addr, buf);
    return buf;
}

pub fn peekString(alloc: std.mem.Allocator, mem: anytype, addr: u16, sentinel: u8) !std.ArrayList(u8) {
    var buf = try std.ArrayList(u8).initCapacity(alloc, 256);
    errdefer buf.deinit(alloc);

    var offset: u16 = 0;
    while (true) {
        const byte = mem.peek8(@intCast(addr + offset));
        if (byte == sentinel) break;
        try buf.append(alloc, byte);
        offset += 1;
    }

    return buf;
}

pub fn pokeString(mem: anytype, addr: u16, str: []const u8, sentinel: u8) void {
    pokeBytes(mem, addr, str);
    mem.poke8(@intCast(addr + str.len), sentinel);
}

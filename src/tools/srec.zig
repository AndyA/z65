// Parse Motorola S-record files.

const std = @import("std");

pub const SRecMetaKind = enum(u8) { Header, Data, Count, NonStandard, StartAddress, Undefined };

pub const SRecKind = enum(u8) {
    S0 = '0',
    S1 = '1',
    S2 = '2',
    S3 = '3',
    S4 = '4',
    S5 = '5',
    S6 = '6',
    S7 = '7',
    S8 = '8',
    S9 = '9',

    const Self = @This();

    pub fn addrLen(self: Self) usize {
        return switch (self) {
            .S1, .S5, .S9 => 2,
            .S2, .S6, .S8 => 3,
            .S3, .S7 => 4,
            else => 0,
        };
    }

    pub fn metaKind(self: Self) SRecMetaKind {
        return switch (self) {
            .S0 => .Header,
            .S1, .S2, .S3 => .Data,
            .S5 => .Count,
            .S6 => .NonStandard,
            .S7, .S8, .S9 => .StartAddress,
            else => .Undefined,
        };
    }
};

pub const SRecError = error{
    InvalidFormat,
    InvalidChecksum,
    InvalidData,
    OutOfBounds,
};

pub const SRec = struct {
    const Self = @This();
    kind: SRecKind,
    byte_count: u8,
    data: std.ArrayList(u8),

    pub fn init(alloc: std.mem.Allocator, line: []const u8) !Self {
        if (line.len < 10 or line[0] != 'S' or line[1] < '0' or line[1] > '9')
            return SRecError.InvalidFormat;

        const kind: SRecKind = @enumFromInt(line[1]);
        const byte_count: u8 = std.fmt.parseInt(u8, line[2..4], 16) catch
            return SRecError.InvalidData;

        if (byte_count * 2 != line.len - 4)
            return SRecError.InvalidFormat;

        var data = try std.ArrayList(u8).initCapacity(alloc, byte_count);
        errdefer data.deinit(alloc);

        data.items.len = byte_count;
        for (0..byte_count) |i| {
            const pos = 4 + i * 2;
            const byte_str = line[pos .. pos + 2];
            data.items[i] = std.fmt.parseInt(u8, byte_str, 16) catch
                return SRecError.InvalidData;
        }

        const rec = Self{
            .kind = kind,
            .byte_count = byte_count,
            .data = data,
        };

        try rec.check();
        return rec;
    }

    fn check(self: Self) !void {
        const payload = self.payloadBytes();
        const want: u8 = self.data.items[self.data.items.len - 1];
        var got: u32 = self.byte_count;
        for (payload) |byte|
            got += byte;

        got = 0xFF - (got & 0xFF);
        if (got != want)
            return SRecError.InvalidChecksum;
    }

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        self.data.deinit(alloc);
    }

    fn payloadBytes(self: Self) []const u8 {
        return self.data.items[0 .. self.data.items.len - 1];
    }

    fn addrBytes(self: Self) []const u8 {
        const payload = self.payloadBytes();
        return payload[0..self.kind.addrLen()];
    }

    pub fn addr(self: Self) u32 {
        var ad: u32 = 0;
        for (self.addrBytes()) |byte|
            ad = ad << 8 | byte;
        return ad;
    }

    pub fn dataBytes(self: Self) []const u8 {
        const addr_len = self.kind.addrLen();
        const payload = self.payloadBytes();
        return payload[addr_len..];
    }
};

test "SRec" {
    const alloc = std.testing.allocator;
    const expect = std.testing.expect;
    const line = "S119000A0000000000000000008001C38241007F001F71800FFF38";
    var rec = try SRec.init(alloc, line);
    defer rec.deinit(alloc);
    try expect(rec.kind == SRecKind.S1);
    try expect(rec.byte_count == 0x19);
    try expect(rec.addr() == 0x000A);
}

pub const SRecFile = struct {
    const Self = @This();
    records: std.ArrayList(SRec),

    pub fn init(alloc: std.mem.Allocator, file: []const u8) !Self {
        const records = try std.ArrayList(SRec).initCapacity(alloc, 1000);
        var self = Self{ .records = records };
        errdefer self.deinit(alloc);

        var iter = std.mem.splitScalar(u8, file, '\n');
        while (iter.next()) |line| {
            if (line.len == 0)
                continue;
            var rec = try SRec.init(alloc, line);
            errdefer rec.deinit(alloc);
            try self.records.append(alloc, rec);
        }

        return self;
    }

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        for (self.records.items) |*rec|
            rec.deinit(alloc);
        self.records.deinit(alloc);
    }

    pub fn startAddr(self: Self) ?u32 {
        for (self.records.items) |rec| {
            if (rec.kind.metaKind() == .StartAddress) {
                return rec.addr();
            }
        }
        return null;
    }

    pub fn materialize(self: Self, buf: []u8) !void {
        for (self.records.items) |rec| {
            if (rec.kind.metaKind() != .Data)
                continue;

            const addr = rec.addr();
            const data = rec.dataBytes();
            if (addr + data.len > buf.len)
                return SRecError.OutOfBounds;

            @memcpy(buf[addr .. addr + data.len], data);
        }
    }
};

test "SRecFile" {
    const alloc = std.testing.allocator;
    const expect = std.testing.expect;
    const file = @embedFile("../cpu/test/data/srec.s19");
    var sr = try SRecFile.init(alloc, file);
    defer sr.deinit(alloc);
    // for (sr.records.items) |rec| {
    //     std.debug.print("Record: S{c}: {x}\n", .{ @intFromEnum(rec.kind), rec.addr() });
    // }
    try expect(sr.startAddr() == 0x0400);

    var buf: [0x10000]u8 = @splat(0x00);
    try sr.materialize(&buf);
    try expect(buf[0x0400] == 0xd8);
    try expect(buf[0xffff] == 0x37);
}

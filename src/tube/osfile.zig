const std = @import("std");
const ct = @import("../cpu/cpu_tools.zig");

pub fn writeFile(name: []const u8, bytes: []const u8) !void {
    // TODO atomic
    const file = try std.fs.cwd().createFile(name, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

pub const OSFILE = struct {
    const Self = @This();

    filename: u16,
    load_addr: u32,
    exec_addr: u32,
    start_addr: u32,
    end_addr: u32,

    pub fn format(self: Self, writer: std.io.Writer) std.io.Writer.Error!void {
        try writer.print(
            \\filename: {x:0>4} load: {x:0>8} exec: {x:0>8} start: {x:0>8} end: {x:0>8}
        , .{ self.filename, self.load_addr, self.exec_addr, self.start_addr, self.end_addr });
    }

    fn save(self: Self, alloc: std.mem.Allocator, cpu: anytype) !u8 {
        var file_name = try ct.peekString(alloc, cpu, self.filename, 0x0D);
        defer file_name.deinit();

        const lang = cpu.os.lang;
        if (@hasDecl(@TypeOf(lang.*), "hook:save")) {
            if (try lang.@"hook:save"(self, cpu, file_name.items)) return 0x01;
        }

        const size: u16 = @intCast(self.end_addr - self.start_addr);
        const bytes = try ct.peekBytesAlloc(alloc, cpu, @intCast(self.start_addr), size);
        defer alloc.free(bytes);

        try writeFile(file_name.items, bytes);

        return 0x01;
    }

    fn load(self: Self, alloc: std.mem.Allocator, cpu: anytype) !u8 {
        var file_name = try ct.peekString(alloc, cpu, self.filename, 0x0D);
        defer file_name.deinit();

        const lang = cpu.os.lang;
        if (@hasDecl(@TypeOf(lang.*), "hook:load")) {
            if (try lang.@"hook:load"(self, cpu, file_name.items)) return 0x01;
        }

        var buf: [0x10000]u8 = undefined;
        const prog = try std.fs.cwd().readFile(file_name.items, &buf);
        ct.pokeBytes(cpu, @intCast(self.load_addr), prog);
        return 0x01;
    }

    pub fn despatch(self: Self, alloc: std.mem.Allocator, cpu: anytype) !void {
        switch (cpu.A) {
            0x00 => cpu.A = try self.save(alloc, cpu),
            0xFF => cpu.A = try self.load(alloc, cpu),
            else => std.debug.print("Unknown OSFILE operation: {x}\n", .{cpu.A}),
        }
    }
};

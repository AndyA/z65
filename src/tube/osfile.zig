const std = @import("std");
const ct = @import("../tools/cpu_tools.zig");

pub fn writeFile(name: []const u8, bytes: []const u8) !void {
    // TODO atomic
    const file = try std.fs.cwd().createFile(name, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

pub const FileInfo = struct {
    const Self = @This();
    name: [12]u8,
    load_addr: u32,
    exec_addr: u32,
    file_size: u32,

    pub fn init(file_name: []const u8, load_addr: u32, exec_addr: u32, file_size: u32) Self {
        var name: [12]u8 = @splat(' ');
        const name_len = @min(name.len, file_name.len);
        @memcpy(name[0..name_len], file_name[0..name_len]);
        return Self{
            .name = name,
            .load_addr = load_addr,
            .exec_addr = exec_addr,
            .file_size = file_size,
        };
    }

    pub fn format(self: Self, writer: *std.io.Writer) std.io.Writer.Error!void {
        try writer.print(
            \\{s} {X:0>8} {X:0>8} {X:0>8}
        , .{ self.name, self.load_addr, self.exec_addr, self.file_size });
    }
};

test FileInfo {
    const fi = FileInfo.init("$.clocksp", 0x800, 0x8023, 0x13d);
    std.debug.print("info: {f}\n", .{fi});
}

pub const OSFILE_CB = struct {
    const Self = @This();
    load_addr: u32 = 0,
    exec_addr: u32 = 0,
    start_addr: u32 = 0,
    end_addr: u32 = 0,

    pub fn save(self: Self, alloc: std.mem.Allocator, file_name: []const u8, cpu: anytype) !void {
        const size: u16 = @intCast(self.end_addr - self.start_addr);
        const bytes = try ct.peekBytesAlloc(alloc, cpu, @intCast(self.start_addr), size);
        defer alloc.free(bytes);

        try writeFile(file_name, bytes);
    }

    pub fn load(self: Self, alloc: std.mem.Allocator, file_name: []const u8, cpu: anytype) !void {
        _ = alloc;
        var buf: [0x10000]u8 = undefined;
        const prog = try std.fs.cwd().readFile(file_name, &buf);
        ct.pokeBytes(cpu, @intCast(self.load_addr), prog);
    }
};

pub const OSFILE = struct {
    const Self = @This();

    filename: u16,
    cb: OSFILE_CB,

    pub fn format(self: Self, writer: *std.io.Writer) std.io.Writer.Error!void {
        try writer.print(
            \\filename: {x:0>4} load: {x:0>8} exec: {x:0>8} start: {x:0>8} end: {x:0>8}
        , .{
            self.filename,
            self.cb.load_addr,
            self.cb.exec_addr,
            self.cb.start_addr,
            self.cb.end_addr,
        });
    }

    fn save(self: Self, alloc: std.mem.Allocator, cpu: anytype) !u8 {
        var file_name = try ct.peekString(alloc, cpu, self.filename, 0x0D);
        defer file_name.deinit(alloc);

        const lang = cpu.os.lang;
        if (@hasDecl(@TypeOf(lang.*), "hook:save")) {
            if (try lang.@"hook:save"(self, cpu, file_name.items)) return 0x01;
        }

        try self.cb.save(alloc, file_name.items, cpu);

        return 0x01;
    }

    fn load(self: Self, alloc: std.mem.Allocator, cpu: anytype) !u8 {
        var file_name = try ct.peekString(alloc, cpu, self.filename, 0x0D);
        defer file_name.deinit(alloc);

        const lang = cpu.os.lang;
        if (@hasDecl(@TypeOf(lang.*), "hook:load")) {
            if (try lang.@"hook:load"(self, cpu, file_name.items)) return 0x01;
        }

        try self.cb.load(alloc, file_name.items, cpu);

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

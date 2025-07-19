const std = @import("std");
const ct = @import("cpu/cpu_tools.zig");

const Symbols = @import("tube/os.zig").Symbols;

fn hashBytes(text: []const u8) u256 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(text);
    return @bitCast(h.finalResult());
}

pub const HiBasicError = error{
    ProgramTooLarge,
};

pub const HiBasicAutoSave = enum { AutoSave, NoAutoSave };

pub const HiBasic = struct {
    const Self = @This();
    const LOAD_ADDR = @intFromEnum(Symbols.HIMEM);
    const HIMEM = 0x06;
    const TOP = 0x12;
    const PAGE_HI = 0x18;

    alloc: std.mem.Allocator,
    reader: *std.io.Reader,
    writer: *std.io.Writer,

    ram: *[0x10000]u8,
    snapshot_file: ?[]const u8 = null,
    auto_save: HiBasicAutoSave,
    started: bool = false,
    prog_hash: u256 = 0,

    pub fn init(
        alloc: std.mem.Allocator,
        reader: *std.io.Reader,
        writer: *std.io.Writer,
        ram: *[0x10000]u8,
        snapshot_file: ?[]const u8,
        auto_save: HiBasicAutoSave,
    ) Self {
        return Self{
            .alloc = alloc,
            .reader = reader,
            .writer = writer,
            .ram = ram,
            .snapshot_file = snapshot_file,
            .auto_save = auto_save,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn @"hook:readline"(self: *Self, cpu: anytype) !?[]const u8 {
        if (!self.started) {
            self.started = true;
            try self.onStartup(cpu);
        } else {
            const hash = hashBytes(self.getProgram(cpu));
            if (self.prog_hash != 0 and self.prog_hash != hash)
                try self.onCodeChange(cpu);
            self.prog_hash = hash;
        }
        return null;
    }

    fn onStartup(self: *Self, cpu: anytype) !void {
        if (self.snapshot_file) |file| {
            if (try self.loadSnapshot(cpu, file)) {
                try self.writer.print("\nLoaded {s}\n>", .{file});
            }
        }
    }

    fn onCodeChange(self: *Self, cpu: anytype) !void {
        if (self.auto_save == .AutoSave) {
            if (self.snapshot_file) |file| {
                try self.saveSnapshot(cpu, file);
            }
        }
    }

    pub fn reset(self: *Self, cpu: anytype) void {
        const rom_image = @embedFile("roms/HiBASIC.rom");
        @memcpy(self.ram[LOAD_ADDR .. LOAD_ADDR + rom_image.len], rom_image);
        cpu.PC = @intCast(LOAD_ADDR);
        cpu.A = 0x01;
    }

    pub fn shutDown(self: *Self, cpu: anytype) !void {
        try self.writer.print("\n", .{});
        if (self.snapshot_file) |file| {
            try self.saveSnapshot(cpu, file);
            try self.writer.print("Saved {s}\n", .{file});
        }
        try self.writer.print("Bye!\n", .{});
    }

    pub fn getPage(self: Self, cpu: anytype) u16 {
        _ = self;
        const page_hi: u16 = @intCast(cpu.peek8(PAGE_HI));
        const page: u16 = page_hi << 8;
        return page;
    }

    pub fn getProgram(self: Self, cpu: anytype) []const u8 {
        const page = self.getPage(cpu);
        const top: u16 = cpu.peek16(TOP);
        return self.ram[page..top];
    }

    pub fn setProgram(self: *Self, cpu: anytype, prog: []const u8) !void {
        const page = self.getPage(cpu);
        const top: u16 = @intCast(page + prog.len);
        const himem: u16 = cpu.peek16(HIMEM);
        if (top > himem)
            return HiBasicError.ProgramTooLarge;
        @memcpy(self.ram[page..top], prog);
        cpu.poke16(TOP, top);
    }

    fn saveSnapshot(self: Self, cpu: anytype, file: []const u8) !void {
        const prog = self.getProgram(cpu);
        const fh = try std.fs.cwd().createFile(file, .{ .truncate = true });
        defer fh.close();
        try fh.writeAll(prog);
    }

    fn loadSnapshot(self: *Self, cpu: anytype, file: []const u8) !bool {
        var buf: [0x10000]u8 = undefined;
        const prog = std.fs.cwd().readFile(file, buf[0..]) catch |err| {
            if (err == error.FileNotFound) return false;
            return err;
        };
        try self.setProgram(cpu, prog);
        return true;
    }
};

const std = @import("std");
const ct = @import("cpu/cpu_tools.zig");
const bb = @import("bbc_basic.zig");
const cvt = @import("basic/converter.zig");
const code = @import("basic/code.zig");

const Symbols = @import("tube/os.zig").Symbols;

const hashBytes = @import("tools/util.zig").hashBytes;

pub const HiBasicError = error{
    ProgramTooLarge,
};

pub fn lastModified(file: []const u8) !i128 {
    const fh = std.fs.cwd().openFile(file, .{}) catch |err| {
        if (err == error.FileNotFound) return 0; // No snapshot file
        return err;
    };
    defer fh.close();
    const s = try fh.stat();
    return s.mtime;
}

pub const HiBasicSnapshot = struct {
    const Self = @This();
    file: []const u8,
    auto_save: bool = false,
    auto_load: bool = false,
};

pub const HiBasic = struct {
    const Self = @This();
    const LOAD_ADDR = @intFromEnum(Symbols.HIMEM);
    const HIMEM = 0x06;
    const NEXTP = 0x0b; // current program line pointer
    const TOP = 0x12;
    const PAGE_HI = 0x18;
    const CMD_BUF = 0x700;

    alloc: std.mem.Allocator,
    reader: *std.io.Reader,
    writer: *std.io.Writer,

    ram: *[0x10000]u8,
    bin_snapshot: ?HiBasicSnapshot,
    src_snapshot: ?HiBasicSnapshot,
    src_last_modified: i128 = 0,
    started: bool = false,
    prog_hash: u256 = 0,

    pub fn init(
        alloc: std.mem.Allocator,
        reader: *std.io.Reader,
        writer: *std.io.Writer,
        ram: *[0x10000]u8,
        bin_snapshot: ?HiBasicSnapshot,
        src_snapshot: ?HiBasicSnapshot,
    ) !Self {
        return Self{
            .alloc = alloc,
            .reader = reader,
            .writer = writer,
            .ram = ram,
            .bin_snapshot = bin_snapshot,
            .src_snapshot = src_snapshot,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn @"hook:reset"(self: *Self, cpu: anytype) !void {
        self.started = false;
        cpu.os.startCapture();
    }

    pub fn commandMode(self: *Self, cpu: anytype) bool {
        _ = self;
        const nextp = cpu.peek16(Self.NEXTP);
        const buf = cpu.peek16(ct.getXY(cpu));
        return nextp == CMD_BUF and buf == CMD_BUF;
    }

    pub fn @"hook:readline"(self: *Self, cpu: anytype) !?[]const u8 {
        if (!commandMode(self, cpu))
            return null;

        if (!self.started) {
            self.started = true;
            try self.onStartup(cpu);
            const output = cpu.os.takeCapture();
            try self.writer.print("{s}", .{output});
        }

        const hash = hashBytes(self.getProgram(cpu));
        if (self.prog_hash != 0 and self.prog_hash != hash)
            try self.onCodeChange(cpu);
        self.prog_hash = hash;

        return null;
    }

    pub fn @"hook:sendline"(self: *Self, cpu: anytype, line: []const u8) ![]const u8 {
        if (!self.commandMode(cpu))
            return line;

        if (self.src_snapshot) |snap| {
            if (snap.auto_load) {
                const lm = try lastModified(snap.file);
                if (lm == 0) return line;
                const changed = self.src_last_modified != 0 and self.src_last_modified != lm;
                self.src_last_modified = lm;

                if (changed) {
                    const prog = try std.fs.cwd().readFileAlloc(self.alloc, snap.file, 0x10000);
                    defer self.alloc.free(prog);

                    const bin = try cvt.parseSource(self.alloc, prog);
                    defer bin.deinit();

                    const current = self.getProgram(cpu);
                    if (!std.mem.eql(u8, bin.bytes, current)) {
                        try self.setProgram(cpu, bin.bytes);
                        code.clearVariables(self.ram);
                    }
                }
            }
        }

        return line;
    }

    fn onStartup(self: *Self, cpu: anytype) !void {
        if (self.bin_snapshot) |snap| {
            if (try self.loadBinSnapshot(cpu, snap.file)) {
                try self.writer.print("Loaded {s}\n", .{snap.file});
            }
        }
        if (self.src_snapshot) |snap| {
            self.src_last_modified = try lastModified(snap.file);
        }
    }

    fn onCodeChange(self: *Self, cpu: anytype) !void {
        if (self.bin_snapshot) |snap| {
            if (snap.auto_save) {
                try self.saveBinSnapshot(cpu, snap.file);
            }
        }

        if (self.src_snapshot) |snap| {
            if (snap.auto_save) {
                const prog = self.getProgram(cpu);
                const source = try cvt.stringifyBinary(self.alloc, prog);
                defer source.deinit();
                const fh = try std.fs.cwd().createFile(snap.file, .{ .truncate = true });
                defer fh.close();
                try fh.writeAll(source.bytes);
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
        if (self.bin_snapshot) |snap| {
            try self.saveBinSnapshot(cpu, snap.file);
            try self.writer.print("Saved {s}\n", .{snap.file});
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
        self.prog_hash = hashBytes(prog);
    }

    fn saveBinSnapshot(self: Self, cpu: anytype, file: []const u8) !void {
        const prog = self.getProgram(cpu);
        const fh = try std.fs.cwd().createFile(file, .{ .truncate = true });
        defer fh.close();
        try fh.writeAll(prog);
    }

    fn loadBinSnapshot(self: *Self, cpu: anytype, file: []const u8) !bool {
        const prog = std.fs.cwd().readFileAlloc(self.alloc, file, 0x10000) catch |err| {
            if (err == error.FileNotFound) return false;
            return err;
        };
        defer self.alloc.free(prog);
        try self.setProgram(cpu, prog);
        return true;
    }
};

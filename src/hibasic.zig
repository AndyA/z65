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

pub const HiBasicSnapshot = struct {
    snapshot_file: ?[]const u8 = null,
    auto_save: HiBasicAutoSave,
};

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
    bin_snapshot: HiBasicSnapshot,
    src_snapshot: HiBasicSnapshot,
    started: bool = false,
    interactive: bool = true,
    prog_hash: u256 = 0,
    input_queue: std.ArrayList([]const u8),

    pub fn init(
        alloc: std.mem.Allocator,
        reader: *std.io.Reader,
        writer: *std.io.Writer,
        ram: *[0x10000]u8,
        bin_snapshot: HiBasicSnapshot,
        src_snapshot: HiBasicSnapshot,
    ) !Self {
        return Self{
            .alloc = alloc,
            .reader = reader,
            .writer = writer,
            .ram = ram,
            .bin_snapshot = bin_snapshot,
            .src_snapshot = src_snapshot,
            .input_queue = try std.ArrayList([]const u8).initCapacity(alloc, 100),
        };
    }

    pub fn deinit(self: *Self) void {
        self.input_queue.deinit();
    }

    pub fn @"hook:reset"(self: *Self, cpu: anytype) !void {
        self.started = false;
        cpu.os.startCapture();
    }

    pub fn @"hook:readline"(self: *Self, cpu: anytype) !?[]const u8 {
        if (!self.started) {
            self.started = true;
            try self.onStartup(cpu);
            const output = cpu.os.takeCapture();
            try self.writer.print("{s}", .{output});
        }

        // Anything in the input queue?
        if (self.inputPending())
            return self.input_queue.orderedRemove(0);

        if (!self.interactive) {
            self.interactive = true;
            _ = cpu.os.takeCapture();
            try self.onInteractive(cpu);
        }

        const hash = hashBytes(self.getProgram(cpu));
        if (self.prog_hash != 0 and self.prog_hash != hash)
            try self.onCodeChange(cpu);
        self.prog_hash = hash;

        // Try the queue again
        if (self.inputPending())
            return self.input_queue.orderedRemove(0);

        return null;
    }

    pub fn inputPending(self: Self) bool {
        return self.input_queue.items.len != 0;
    }

    pub fn scheduleCommand(self: *Self, cmd: []const u8) !void {
        try self.input_queue.append(cmd);
        self.interactive = false;
    }

    fn onStartup(self: *Self, cpu: anytype) !void {
        if (self.bin_snapshot.snapshot_file) |file| {
            if (try self.loadBinSnapshot(cpu, file)) {
                try self.writer.print("Loaded {s}\n", .{file});
            }
        }
    }

    fn onCodeChange(self: *Self, cpu: anytype) !void {
        if (self.bin_snapshot.auto_save == .AutoSave) {
            if (self.bin_snapshot.snapshot_file) |file| {
                try self.saveBinSnapshot(cpu, file);
            }
        }

        if (self.src_snapshot.auto_save == .AutoSave) {
            try self.scheduleCommand("*LANGUAGE CALLBACK code_change");
        }
    }

    fn onInteractive(self: *Self, cpu: anytype) !void {
        _ = self;
        _ = cpu;
    }

    pub fn onCallback(self: *Self, cpu: anytype, callback: []const u8) !void {
        if (std.mem.eql(u8, callback, "code_change")) {
            if (self.src_snapshot.snapshot_file) |file| {
                try self.saveSrcSnapshot(cpu, file);
            }
            return;
        }
    }

    pub fn runScript(self: *Self, cpu: anytype, script: []const []const u8) ![]const u8 {
        for (script) |cmd|
            try self.scheduleCommand(cmd);
        try self.scheduleCommand(""); // A NOP to finish
        cpu.os.startCapture();
        while (!cpu.stopped and self.inputPending())
            cpu.step();
        const output = cpu.os.peekCapture();
        return output[1 .. output.len - 1];
    }

    pub fn reset(self: *Self, cpu: anytype) void {
        const rom_image = @embedFile("roms/HiBASIC.rom");
        @memcpy(self.ram[LOAD_ADDR .. LOAD_ADDR + rom_image.len], rom_image);
        cpu.PC = @intCast(LOAD_ADDR);
        cpu.A = 0x01;
    }

    pub fn shutDown(self: *Self, cpu: anytype) !void {
        try self.writer.print("\n", .{});
        if (self.bin_snapshot.snapshot_file) |file| {
            try self.saveBinSnapshot(cpu, file);
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
        self.prog_hash = hashBytes(prog);
    }

    fn saveSrcSnapshot(self: *Self, cpu: anytype, file: []const u8) !void {
        const output = try self.runScript(cpu, &.{
            "LIST",
        });

        const fh = try std.fs.cwd().createFile(file, .{ .truncate = true });
        defer fh.close();
        try fh.writeAll(output);
    }

    fn saveBinSnapshot(self: Self, cpu: anytype, file: []const u8) !void {
        const prog = self.getProgram(cpu);
        const fh = try std.fs.cwd().createFile(file, .{ .truncate = true });
        defer fh.close();
        try fh.writeAll(prog);
    }

    fn loadBinSnapshot(self: *Self, cpu: anytype, file: []const u8) !bool {
        var buf: [0x10000]u8 = undefined;
        const prog = std.fs.cwd().readFile(file, buf[0..]) catch |err| {
            if (err == error.FileNotFound) return false;
            return err;
        };
        try self.setProgram(cpu, prog);
        return true;
    }
};

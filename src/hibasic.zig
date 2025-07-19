const std = @import("std");
const ct = @import("cpu/cpu_tools.zig");

const Symbols = @import("tube/os.zig").Symbols;

pub const HiBasicError = error{
    ProgramTooLarge,
};

pub const HiBasic = struct {
    const Self = @This();
    const LOAD_ADDR = @intFromEnum(Symbols.HIMEM);
    const HIMEM = 0x06;
    const TOP = 0x12;
    const PAGE_HI = 0x18;

    ram: *[0x10000]u8,
    snapshot_file: ?[]const u8 = null,
    started: bool = false,

    pub fn init(ram: *[0x10000]u8, snapshot_file: ?[]const u8) Self {
        return Self{
            .ram = ram,
            .snapshot_file = snapshot_file,
        };
    }

    pub fn @"hook:readline"(self: *Self, os: anytype, cpu: anytype) !?[]const u8 {
        _ = os;
        // _ = cpu;
        if (!self.started) {
            self.started = true;
            if (self.snapshot_file) |file| {
                if (try self.loadSnapshot(cpu, file)) {
                    std.debug.print("\nLoaded snapshot from {s}.\n>", .{file});
                }
            }
        }
        return null;
    }

    pub fn installInHost(self: *Self, cpu: anytype) void {
        const rom_image = @embedFile("roms/HiBASIC.rom");
        ct.pokeBytes(cpu, LOAD_ADDR, rom_image);
        self.reset(cpu);
    }

    pub fn reset(self: *Self, cpu: anytype) void {
        _ = self;
        cpu.reset();
        cpu.PC = @intCast(LOAD_ADDR);
        cpu.A = 0x01;
    }

    pub fn shutDown(self: *Self, cpu: anytype) !void {
        std.debug.print("\n", .{});
        if (self.snapshot_file) |file| {
            try self.saveSnapshot(cpu, file);
        }
        std.debug.print("Bye!\n", .{});
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
        std.debug.print("Saved snapshot to {s}\n", .{file});
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

const std = @import("std");
const ct = @import("cpu/cpu_tools.zig");
const cvt = @import("basic/converter.zig");
const code = @import("basic/code.zig");
const kw = @import("basic/keywords.zig");
const osfile = @import("tube/osfile.zig");

const Symbols = @import("tube/os.zig").Symbols;

const hashBytes = @import("tools/util.zig").hashBytes;

pub const HiBasicError = error{
    ProgramTooLarge,
    NoFileName,
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

fn isFileCommand(tok: u8) bool {
    return tok == @intFromEnum(kw.KeywordsEnum.LOAD) or
        tok == @intFromEnum(kw.KeywordsEnum.SAVE) or
        tok == @intFromEnum(kw.KeywordsEnum.CHAIN);
}

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
    last_modified: i128 = 0,
    started: bool = false,
    prog_hash: u256 = 0,
    current_file: ?[]const u8 = null,
    auto_load: bool = true,
    auto_save: bool = true,

    pub fn init(
        alloc: std.mem.Allocator,
        reader: *std.io.Reader,
        writer: *std.io.Writer,
        ram: *[0x10000]u8,
    ) !Self {
        return Self{
            .alloc = alloc,
            .reader = reader,
            .writer = writer,
            .ram = ram,
        };
    }

    pub fn deinit(self: *Self) void {
        self.clearCurrentFile();
    }

    pub fn commandMode(self: *Self, cpu: anytype) bool {
        _ = self;
        const nextp = cpu.peek16(Self.NEXTP);
        const buf = cpu.peek16(ct.getXY(cpu));
        return nextp == CMD_BUF and buf == CMD_BUF;
    }

    pub fn clearCurrentFile(self: *Self) void {
        if (self.current_file) |file| {
            self.alloc.free(file);
            self.current_file = null;
        }
    }

    pub fn setCurrentFile(self: *Self, name: []const u8) !void {
        if (self.current_file) |file| {
            if (std.mem.eql(u8, file, name)) return;
            self.alloc.free(file);
        }
        self.current_file = try self.alloc.dupe(u8, name);
        // std.debug.print("Editing {s}\n", .{self.current_file.?});
    }

    pub fn @"hook:readline"(self: *Self, cpu: anytype) !?[]const u8 {
        if (!commandMode(self, cpu))
            return null;

        if (!self.started) {
            self.started = true;
            try self.onStartup(cpu);
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

        if (self.current_file) |file| {
            if (self.auto_load) {
                const lm = try lastModified(file);
                if (lm == 0) return line;
                const changed = self.last_modified != 0 and self.last_modified != lm;
                self.last_modified = lm;

                if (changed) {
                    try self.loadSource(cpu, file);
                }
            }
        }

        return line;
    }

    fn commandContext(self: Self, cpu: anytype, pred: fn (u8) bool) bool {
        _ = self;
        var nextp = cpu.peek16(Self.NEXTP);
        const cutoff = nextp -| 0x100;
        while (nextp > cutoff) {
            nextp -= 1;
            const c = cpu.peek8(nextp);
            if (c == '"') {
                nextp -= 1;
                while (cpu.peek8(nextp) != '"') nextp -= 1;
                continue;
            }
            if (pred(c)) return true;
            if (c == 0x0D or c == ':') return false;
        }
        return false;
    }

    fn shouldIntercept(
        self: Self,
        osf: osfile.OSFILE,
        cpu: anytype,
        name: []const u8,
    ) bool {
        const page = self.getPage(cpu);
        return self.commandContext(cpu, isFileCommand) and
            (std.ascii.endsWithIgnoreCase(name, ".bas") or name.len == 0) and
            (osf.load_addr == page or osf.start_addr == page);
    }

    fn defaultName(self: Self, name: []const u8) ![]const u8 {
        if (name.len > 0) return name;
        if (self.current_file) |file| return file;
        return HiBasicError.NoFileName;
    }

    pub fn @"hook:load"(
        self: *Self,
        osf: osfile.OSFILE,
        cpu: anytype,
        name: []const u8,
    ) !bool {
        if (self.shouldIntercept(osf, cpu, name)) {
            const real_name = try self.defaultName(name);
            try self.loadSource(cpu, real_name);
            try self.setCurrentFile(real_name);
            return true;
        }

        return false;
    }

    pub fn @"hook:save"(
        self: *Self,
        osf: osfile.OSFILE,
        cpu: anytype,
        name: []const u8,
    ) !bool {
        if (self.shouldIntercept(osf, cpu, name)) {
            const real_name = try self.defaultName(name);
            try self.saveSource(cpu, real_name);
            try self.setCurrentFile(real_name);
            return true;
        }

        return false;
    }

    fn loadSource(self: *Self, cpu: anytype, file: []const u8) !void {
        var buf: [0x10000]u8 = undefined;
        const prog = try std.fs.cwd().readFile(file, &buf);

        const bin = try cvt.parseSource(self.alloc, prog);
        defer self.alloc.free(bin);

        const current = self.getProgram(cpu);
        if (!std.mem.eql(u8, bin, current)) {
            try self.setProgram(cpu, bin);
            code.clearVariables(self.ram);
        }
    }

    pub fn saveSource(self: Self, cpu: anytype, file: []const u8) !void {
        const prog = self.getProgram(cpu);
        const source = try cvt.stringifyBinary(self.alloc, prog);
        defer self.alloc.free(source);
        try osfile.writeFile(file, source);
    }

    fn onStartup(self: *Self, cpu: anytype) !void {
        if (self.current_file) |file| {
            self.loadSource(cpu, file) catch |err| {
                if (err == error.FileNotFound) return;
                return err;
            };
            self.last_modified = try lastModified(file);
        }
    }

    fn onCodeChange(self: *Self, cpu: anytype) !void {
        if (self.current_file) |file| {
            if (self.auto_save) {
                try self.saveSource(cpu, file);
            }
        }

        const prog = self.getProgram(cpu);
        if (prog.len == 2) { // NEW?
            self.clearCurrentFile();
        }
    }

    pub fn reset(self: *Self, cpu: anytype) void {
        const rom_image = @embedFile("roms/HiBASIC.rom");
        @memcpy(self.ram[LOAD_ADDR .. LOAD_ADDR + rom_image.len], rom_image);
        cpu.PC = @intCast(LOAD_ADDR);
        cpu.A = 0x01;
    }

    pub fn shutDown(self: *Self, cpu: anytype) !void {
        _ = cpu;
        try self.writer.print("\nBye!\n", .{});
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

const std = @import("std");
const ct = @import("tools/cpu_tools.zig");
const cvt = @import("basic/converter.zig");
const code = @import("basic/code.zig");
const constants = @import("basic/constants.zig");
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

pub const HiBasicConfig = struct {
    prog_name: ?[]const u8 = null,
    chain: bool = false,
    quit: bool = false,
    sync: bool = false,
    exec: []const []const u8 = &[_][]u8{},
};

pub const HiBasicExec = struct {
    const Self = @This();
    alloc: std.mem.Allocator,
    source: []const u8,
    reader: std.Io.Reader,

    pub fn init(alloc: std.mem.Allocator, source: []const u8) !Self {
        const dup_src = try alloc.dupe(u8, source);
        return Self{
            .alloc = alloc,
            .source = dup_src,
            .reader = std.Io.Reader.fixed(dup_src),
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.source);
    }

    pub fn readLine(self: *Self) !?[]const u8 {
        return self.reader.takeDelimiter('\n');
    }
};

pub const HiBasic = struct {
    const Self = @This();
    const LOAD_ADDR = @intFromEnum(Symbols.HIMEM);

    alloc: std.mem.Allocator,
    config: HiBasicConfig,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    ram: *[0x10000]u8,

    started: bool = false,
    current_file: ?[]const u8 = null,
    exec: ?HiBasicExec = null,

    last_modified: i128 = 0,
    prog_hash: u256 = 0,
    source_hash: u256 = 0,

    pub fn init(
        alloc: std.mem.Allocator,
        config: HiBasicConfig,
        reader: *std.Io.Reader,
        writer: *std.Io.Writer,
        ram: *[0x10000]u8,
    ) !Self {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        var w = std.Io.Writer.Allocating.fromArrayList(alloc, &buf);
        defer w.deinit();

        if (config.prog_name) |prog| {
            if (config.chain)
                try w.writer.print("CHAIN \"{s}\"\n", .{prog})
            else
                try w.writer.print("LOAD \"{s}\"\n", .{prog});
        }

        for (config.exec) |line|
            try w.writer.print("{s}\n", .{line});

        if (config.quit)
            try w.writer.print("*QUIT", .{});

        var output = w.toArrayList();
        defer output.deinit(alloc);

        return Self{
            .alloc = alloc,
            .config = config,
            .reader = reader,
            .writer = writer,
            .ram = ram,
            .exec = try HiBasicExec.init(alloc, output.items),
        };
    }

    pub fn deinit(self: *Self) void {
        self.clearCurrentFile();
        self.freeExec();
    }

    pub fn freeExec(self: *Self) void {
        if (self.exec) |*exec| {
            exec.deinit();
            self.exec = null;
        }
    }

    pub fn commandMode(self: *Self, cpu: anytype) bool {
        _ = self;
        const nextp = cpu.peek16(constants.ZP.NEXTP);
        const buf = cpu.peek16(ct.getXY(cpu));
        return nextp == constants.CMD_BUF and buf == constants.CMD_BUF;
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
    }

    pub fn @"hook:readline"(self: *Self, cpu: anytype) !?[]const u8 {
        if (!commandMode(self, cpu))
            return null;

        if (self.exec) |*exec| {
            const line = try exec.readLine();
            if (line) |ln| {
                try self.writer.print("{s}\n", .{ln});
                return ln;
            }
            self.freeExec();
            return null;
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
            if (self.config.sync) {
                const lm = try lastModified(file);
                if (lm == 0) return line;
                if (self.last_modified != 0 and self.last_modified != lm) {
                    try self.loadSource(cpu, file);
                }
            }
        }

        return line;
    }

    fn commandContext(self: Self, cpu: anytype, pred: fn (u8) bool) bool {
        _ = self;
        var nextp = cpu.peek16(constants.ZP.NEXTP);
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
            (std.ascii.endsWithIgnoreCase(name, ".bbc") or name.len == 0) and
            (osf.cb.load_addr == page or osf.cb.start_addr == page);
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
            try self.saveSourceForced(cpu, real_name);
            try self.setCurrentFile(real_name);
            return true;
        }

        return false;
    }

    pub fn loadSource(self: *Self, cpu: anytype, file: []const u8) !void {
        const lm = try lastModified(file);

        var buf: [0x10000]u8 = undefined;
        const prog = try std.fs.cwd().readFile(file, &buf);

        const source = try cvt.stringifyBinary(self.alloc, self.getProgram(cpu));
        defer self.alloc.free(source);

        if (!std.mem.eql(u8, prog, source)) {
            const bin = try cvt.parseSource(self.alloc, prog);
            defer self.alloc.free(bin);

            try self.setProgram(cpu, bin);
            code.clearVariables(self.ram);
        }
        self.last_modified = lm;
    }

    pub fn saveSource(self: *Self, cpu: anytype, file: []const u8) !void {
        const prog = self.getProgram(cpu);
        const source = try cvt.stringifyBinary(self.alloc, prog);
        defer self.alloc.free(source);
        const hash = hashBytes(source);
        if (hash != self.source_hash) {
            try osfile.writeFile(file, source);
            self.source_hash = hash;
        }
    }

    pub fn saveSourceForced(self: *Self, cpu: anytype, file: []const u8) !void {
        self.source_hash = 0;
        try self.saveSource(cpu, file);
    }

    fn onCodeChange(self: *Self, cpu: anytype) !void {
        const prog = self.getProgram(cpu);
        if (prog.len == 2) { // NEW?
            self.clearCurrentFile();
        }

        if (self.current_file) |file| {
            if (self.config.sync) {
                try self.saveSource(cpu, file);
            }
        }
    }

    pub fn reset(self: *Self, cpu: anytype) void {
        const rom_image = @embedFile("roms/HiBASIC.rom");
        @memcpy(self.ram[LOAD_ADDR .. LOAD_ADDR + rom_image.len], rom_image);
        cpu.PC = @intCast(LOAD_ADDR);
        cpu.A = 0x01;
    }

    pub fn getPage(self: Self, cpu: anytype) u16 {
        _ = self;
        const page_hi: u16 = @intCast(cpu.peek8(constants.ZP.PAGE_HI));
        const page: u16 = page_hi << 8;
        return page;
    }

    pub fn getProgram(self: Self, cpu: anytype) []const u8 {
        // TODO this fails if PAGE > TOP which seems to happen
        // if you e.g.
        //   >*LOAD basicprog 2000
        //   >PAGE=&2000
        const page = self.getPage(cpu);
        const top: u16 = cpu.peek16(constants.ZP.TOP);
        return self.ram[page..top];
    }

    pub fn setProgram(self: *Self, cpu: anytype, prog: []const u8) !void {
        const page = self.getPage(cpu);
        const top: u16 = @intCast(page + prog.len);
        const himem: u16 = cpu.peek16(constants.ZP.HIMEM);
        if (top > himem)
            return HiBasicError.ProgramTooLarge;
        @memcpy(self.ram[page..top], prog);
        cpu.poke16(constants.ZP.TOP, top);
        self.prog_hash = hashBytes(prog);
    }
};

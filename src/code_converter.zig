const std = @import("std");
const machine = @import("cpu/cpu.zig");
const memory = @import("cpu/memory.zig");
const tube = @import("tube/os.zig");
const hb = @import("hibasic.zig");
const serde = @import("serde.zig").serde;

const constants = @import("tube/constants.zig");
const hashBytes = @import("tools/hasher.zig").hashBytes;

const HIMEM = @intFromEnum(constants.Symbols.HIMEM);
const PAGE = @intFromEnum(constants.Symbols.PAGE);
const OSWORD = @intFromEnum(constants.MOSEntry.OSWORD);
const CLEAR = 0xF523; // Basic's CLEAR routine
const ZP_TOP = 0x12;

const MiniBasic = struct {
    const Self = @This();
    ram: *[0x10000]u8,

    pub fn reset(self: *Self, cpu: anytype) void {
        const rom_image = @embedFile("roms/HiBASIC.rom");
        @memcpy(self.ram[HIMEM .. HIMEM + rom_image.len], rom_image);
        cpu.PC = @intCast(HIMEM);
        cpu.A = 0x01;
    }

    pub fn onCallback(self: *Self, cpu: anytype, callback: []const u8) !void {
        _ = self;
        _ = cpu;
        std.debug.print("Unrecognized callback: {s}\n", .{callback});
    }
};

const TubeOS = tube.TubeOS(MiniBasic);

const Tube65C02 = machine.makeCPU(
    @import("cpu/wdc65c02.zig").InstructionSet65C02,
    @import("cpu/address_modes.zig").AddressModes,
    @import("cpu/instructions.zig").Instructions,
    @import("cpu/alu.zig").ALU65C02,
    memory.FlatMemory,
    machine.NullInterruptSource,
    TubeOS,
    .{ .clear_decimal_on_int = true },
);

const BasicError = error{ BRK, ProgramTooLarge, BadProgram };

fn peek16(bytes: []const u8, addr: u16) u16 {
    if (addr + 1 >= bytes.len) @panic("Out of range");
    return @as(u16, bytes[addr]) | (@as(u16, bytes[addr + 1]) << 8);
}

fn peek16be(bytes: []const u8, addr: u16) u16 {
    if (addr + 1 >= bytes.len) @panic("Out of range");
    return @as(u16, bytes[addr + 1]) | (@as(u16, bytes[addr]) << 8);
}

pub fn getProgram(ram: *[0x10000]u8) []const u8 {
    const top = peek16(ram, ZP_TOP);
    return ram[PAGE..top];
}

pub fn setProgram(ram: *[0x10000]u8, prog: []const u8) !void {
    if (prog.len > HIMEM - PAGE - 0x100)
        return BasicError.ProgramTooLarge;
    @memcpy(ram[PAGE .. PAGE + prog.len], prog);
}

pub fn runHiBasic(
    alloc: std.mem.Allocator,
    ram: *[0x10000]u8,
    reader: *std.io.Reader,
    writer: *std.io.Writer,
) !void {
    var lang = MiniBasic{ .ram = ram };

    var os = try TubeOS.init(alloc, reader, writer, &lang);
    defer os.deinit();

    var cpu = Tube65C02.init(
        memory.FlatMemory{ .ram = ram },
        machine.NullInterruptSource{},
        &os,
    );

    cpu.reset();
    os.reset(&cpu);
    lang.reset(&cpu);

    var brk_seen = false;
    while (!cpu.stopped) {
        if (cpu.peek8(cpu.PC) == 0x00) {
            @branchHint(.unlikely);
            brk_seen = true;
        }
        if (cpu.PC == OSWORD and brk_seen) {
            @branchHint(.unlikely);
            return BasicError.BRK;
        }
        cpu.step();
    }
}

fn isNewline(c: u8) bool {
    return c == '\r' or c == '\n';
}

pub fn cleanBasicOutput(output: *std.ArrayListUnmanaged(u8)) void {
    var ip: usize = 0;
    var op: usize = 0;
    var sol = true; // start of line
    while (ip < output.items.len) : (ip += 1) {
        const c = output.items[ip];
        if (c == '\r') continue;
        if (sol and c == '>') {
            while (ip + 1 < output.items.len and isNewline(output.items[ip + 1]))
                ip += 1;
            continue;
        }
        output.items[op] = c;
        op += 1;
        sol = c == '\n';
    }
    output.items.len = op;
}

test runHiBasic {
    const allocator = std.testing.allocator;
    var r = std.io.Reader.fixed("PRINT PI\n");
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(allocator, &buf);
    defer w.deinit();

    var ram: [0x10000]u8 = @splat(0);
    try runHiBasic(allocator, &ram, &r, &w.writer);

    var output = w.toArrayList();
    defer output.deinit(allocator);

    try std.testing.expectEqualDeep(
        ">3.14159265\n\r>",
        output.items,
    );
}

test "runHiBasic error" {
    const allocator = std.testing.allocator;
    var r = std.io.Reader.fixed(
        \\PRINT PI
        \\make a mistake
        \\PRINT E
        \\PRINT PI * 2
        \\
    );
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(allocator, &buf);
    defer w.deinit();

    var ram: [0x10000]u8 = @splat(0);
    const res = runHiBasic(allocator, &ram, &r, &w.writer);

    try std.testing.expectError(BasicError.BRK, res);

    var output = w.toArrayList();
    defer output.deinit(allocator);
    cleanBasicOutput(&output);

    try std.testing.expectEqualDeep(
        \\3.14159265
        \\Mistake
        \\
    ,
        output.items,
    );
}

pub const Code = struct {
    const Self = @This();
    alloc: std.mem.Allocator,
    bytes: []const u8,
    hash: u256,

    pub fn init(alloc: std.mem.Allocator, bytes: []const u8) !Self {
        const bytes_copy = try alloc.dupe(u8, bytes);
        return Self{
            .alloc = alloc,
            .bytes = bytes_copy,
            .hash = hashBytes(bytes_copy),
        };
    }

    pub fn deinit(self: Self) void {
        self.alloc.free(self.bytes);
    }
};

pub fn validateBinary(prog: []const u8) !void {
    const bp = BasicError.BadProgram;
    var pos: u16 = 0;
    var line: u16 = 0;
    while (true) {
        if (pos + 1 >= prog.len or prog[pos] != 0x0D) return bp;
        if (prog[pos + 1] == 0xFF) {
            if (pos + 2 != prog.len) return bp;
            return;
        }
        if (pos + 3 >= prog.len) return bp;
        const ln = peek16be(prog, pos + 1);
        if (pos > 0 and ln <= line) return bp;
        line = ln;
        const len = prog[pos + 3];
        if (len < 5) return bp;
        pos += len;
        if (pos >= prog.len) return bp;
    }
}

pub fn sourceToBinary(source: Code) !Code {
    var r = std.io.Reader.fixed(source.bytes);
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(source.alloc, &buf);
    defer w.deinit();

    var ram: [0x10000]u8 = @splat(0);
    try runHiBasic(source.alloc, &ram, &r, &w.writer);

    return try Code.init(source.alloc, getProgram(&ram));
}

pub fn hexDump(mem: []const u8) void {
    var pos: usize = 0;
    while (pos < mem.len) : (pos += 16) {
        var avail = @min(16, mem.len - pos);
        const bytes = mem[pos .. pos + avail];
        std.debug.print("{x:0>4} |", .{pos});
        for (bytes) |byte|
            std.debug.print(" {x:0>2}", .{byte});
        while (avail < 16) : (avail += 1)
            std.debug.print("   ", .{});
        std.debug.print(" | ", .{});
        for (bytes) |byte| {
            const rep = if (std.ascii.isPrint(byte)) byte else '.';
            std.debug.print("{c}", .{rep});
        }
        std.debug.print("\n", .{});
    }
}

test sourceToBinary {
    const allocator = std.testing.allocator;

    const prog =
        \\   10 PRINT "Hello, World"
        \\   20 GOTO 10
        \\
    ;

    const source = try Code.init(allocator, prog);
    defer source.deinit();

    const bin = try sourceToBinary(source);
    defer bin.deinit();

    hexDump(bin.bytes);

    try validateBinary(bin.bytes);
}

pub fn binaryToSource(binary: Code) !Code {
    var r = std.io.Reader.fixed(
        \\OLD
        \\LIST
    );
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = std.io.Writer.Allocating.fromArrayList(binary.alloc, &buf);
    defer w.deinit();

    var ram: [0x10000]u8 = @splat(0);
    try setProgram(&ram, binary.bytes);
    try runHiBasic(binary.alloc, &ram, &r, &w.writer);

    var output = w.toArrayList();
    defer output.deinit(binary.alloc);
    cleanBasicOutput(&output);

    return try Code.init(binary.alloc, output.items);
}

test binaryToSource {
    const allocator = std.testing.allocator;

    const prog =
        \\   10 PRINT "Hello, World"
        \\   20 GOTO 10
        \\
    ;

    const in_source = try Code.init(allocator, prog);
    defer in_source.deinit();

    const bin = try sourceToBinary(in_source);
    defer bin.deinit();

    // hexDump(bin.bytes);

    const out_source = try binaryToSource(bin);
    defer out_source.deinit();

    // std.debug.print("{s}", .{out_source.bytes});

    try std.testing.expectEqualDeep(prog, out_source.bytes);
}

fn showChanged(a: []const u8, b: []const u8) void {
    if (a.len != b.len) {
        std.debug.print("length mismatch: a={d}, b={d}", .{ a.len, b.len });
        return;
    }
    for (a, 0..) |ia, i| {
        if (ia != b[i])
            std.debug.print("{x:0>4} {x:0>2} -> {x:0>2}\n", .{ i, ia, b[i] });
    }
}

test "playground" {
    const allocator = std.testing.allocator;
    var ram0: [0x10000]u8 = @splat(0xff);
    var ram1: [0x10000]u8 = @splat(0xff);
    var ram2: [0x10000]u8 = @splat(0xff);
    ram1[255] = 0;
    ram2[255] = 0;
    const prog =
        \\   10 A$ = "Hi!" : PRINT A$
        \\   20 A = 100 : B = 100 : Z = 100
        \\   30 A$ = "A" : B$ = "B" : Z$ = "Z"
        \\   40 DIM a(100) : DIM a$(100) : DIM a% 100
        \\   50 DIM z(100) : DIM z$(100) : DIM z% 100
        \\   60 PROChello
        \\   70 END
        \\   80 DEF PROChello
        \\   90   LOCAL A$
        \\  100   PRINT "Hello, World"
        \\  110 ENDPROC
        \\REN.
        \\LIST
        \\RUN
        \\
    ;
    {
        var r = std.io.Reader.fixed(prog);
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        var w = std.io.Writer.Allocating.fromArrayList(allocator, &buf);
        defer w.deinit();

        try runHiBasic(allocator, &ram1, &r, &w.writer);

        var output = w.toArrayList();
        defer output.deinit(allocator);
        cleanBasicOutput(&output);

        std.debug.print("----\n{s}----\n", .{output.items});
    }

    showChanged(ram0[0..0xb800], ram1[0..0xb800]);

    {
        var r = std.io.Reader.fixed(prog ++
            \\CLEAR
            \\
        );
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        var w = std.io.Writer.Allocating.fromArrayList(allocator, &buf);
        defer w.deinit();

        runHiBasic(allocator, &ram2, &r, &w.writer) catch |err| {
            var output = w.toArrayList();
            defer output.deinit(allocator);
            cleanBasicOutput(&output);
            std.debug.print("----\n{s}----\n", .{output.items});
            return err;
        };
    }

    showChanged(ram1[0..0xb800], ram2[0..0xb800]);
}

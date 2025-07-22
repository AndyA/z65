const std = @import("std");
const machine = @import("../cpu/cpu.zig");
const memory = @import("../cpu/memory.zig");
const tube = @import("../tube/os.zig");

const constants = @import("../tube/constants.zig");

const HIMEM = @intFromEnum(constants.Symbols.HIMEM);
const OSWORD = @intFromEnum(constants.MOSEntry.OSWORD);

pub const RunnerError = error{BRK};

const MiniBasic = struct {
    const Self = @This();
    ram: *[0x10000]u8,

    pub fn reset(self: *Self, cpu: anytype) void {
        const rom_image = @embedFile("../roms/HiBASIC.rom");
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
    @import("../cpu/wdc65c02.zig").InstructionSet65C02,
    @import("../cpu/address_modes.zig").AddressModes,
    @import("../cpu/instructions.zig").Instructions,
    @import("../cpu/alu.zig").ALU65C02,
    memory.FlatMemory,
    machine.NullInterruptSource,
    TubeOS,
    .{ .clear_decimal_on_int = true },
);

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
            return RunnerError.BRK;
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

    try std.testing.expectError(RunnerError.BRK, res);

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

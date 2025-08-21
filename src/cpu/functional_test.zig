const std = @import("std");
const machine = @import("cpu.zig");

pub fn runFunctionalTest(
    allocator: std.mem.Allocator,
    comptime InstructionSet: type,
    comptime ALU: type,
    comptime options: machine.CPUOptions,
    test_code: []const u8,
) !void {
    const memory = @import("memory.zig");
    const srec = @import("../tools/srec.zig");
    const expect = std.testing.expect;

    const TRAP_OPCODE: u8 = 0xBB;

    const TestTrapHandler = struct {
        pub const Self = @This();
        output: std.ArrayList(u8),
        failed: bool = false,
        alloc: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) !Self {
            var output = try std.ArrayList(u8).initCapacity(alloc, 16384);
            errdefer output.deinit();
            return Self{ .output = output, .alloc = alloc };
        }

        pub fn deinit(self: *Self) void {
            self.output.deinit(self.alloc);
        }

        pub fn trap(self: *Self, cpu: anytype, opcode: u8) !void {
            if (opcode == TRAP_OPCODE) {
                const signal: u8 = cpu.fetch8();
                switch (signal) {
                    1 => self.output.append(self.alloc, cpu.A) catch unreachable,
                    2 => {
                        // The test code only asks for input when a test has failed.
                        std.debug.print("Test failure:\n{s}\n", .{self.output.items});
                        cpu.stop();
                        self.failed = true;
                    },
                    3 => cpu.stop(),
                    else => |sig| std.debug.print("Trap signal {d} received\n", .{sig}),
                }
            } else {
                std.debug.print("Illegal instruction: {x} at {f}\n", .{ opcode, cpu });
                @panic("Illegal instruction");
            }
        }
    };

    const CPU = machine.CPU(
        InstructionSet,
        @import("address_modes.zig").AddressModes,
        @import("instructions.zig").Instructions,
        ALU,
        memory.FlatMemory,
        machine.NullInterruptSource,
        TestTrapHandler,
        options,
    );
    var ram: [0x10000]u8 = @splat(0);

    var sr = try srec.SRecFile.init(allocator, test_code);
    defer sr.deinit(allocator);

    const start = sr.startAddr() orelse @panic("No start address found in SRec file");
    try sr.materialize(&ram);

    var trapper = try TestTrapHandler.init(allocator);
    defer trapper.deinit();

    var mc = CPU.init(
        memory.FlatMemory{ .ram = &ram },
        machine.NullInterruptSource{},
        &trapper,
    );

    mc.PC = @intCast(start);
    while (!mc.stopped) {
        mc.step();
    }

    try expect(!trapper.failed);
}

const std = @import("std");
const machine = @import("cpu.zig");
const memory = @import("memory.zig");
const tt = @import("type_tools.zig");
const srec = @import("srec.zig");

pub const PORTAL_OP = 0xbb;

const TRAP_OPCODE: u8 = 0xBB;

const TestTrapHandler = struct {
    pub const Self = @This();
    pub fn trap(self: Self, cpu: anytype, opcode: u8) void {
        _ = self;
        if (opcode == TRAP_OPCODE) {
            const signal: u8 = cpu.fetch8();
            const stdin = std.io.getStdIn().reader();
            switch (signal) {
                1 => {
                    std.debug.print("{c}", .{cpu.A});
                },
                2 => {
                    var buf: [256]u8 = undefined;
                    const res = stdin.readUntilDelimiterOrEof(&buf, '\n') catch |err| {
                        std.debug.print("Error reading input: {s}\n", .{@errorName(err)});
                        return;
                    };
                    if (res) |in| {
                        if (in.len > 0) {
                            cpu.A = in[0];
                        }
                    }
                },
                3 => {
                    std.debug.print("Trap signal 3 received, halting CPU\n", .{});
                    cpu.stopped = true;
                },
                else => |sig| {
                    std.debug.print("Trap signal {d} received\n", .{sig});
                },
            }
        } else {
            @panic("Illegal instruction");
        }
    }
};

const Vanilla65C02 = machine.makeCPU(
    @import("wdc65c02.zig").InstructionSet65C02,
    @import("address_modes.zig").AddressModes,
    @import("instructions.zig").Instructions,
    memory.FlatMemory,
    machine.NullInterruptSource,
    TestTrapHandler,
);

const test_code = @embedFile("test/data/6502_functional_test.s19");

pub fn main() !void {
    var ram: [0x10000]u8 = @splat(0);

    var sr = try srec.SRecFile.init(std.heap.page_allocator, test_code);
    defer sr.deinit();

    const start = sr.startAddr() orelse @panic("No start address found in SRec file");

    try sr.materialize(&ram);

    var trapper = TestTrapHandler{};

    var mc = Vanilla65C02.init(
        memory.FlatMemory{ .ram = &ram },
        machine.NullInterruptSource{},
        &trapper,
    );

    mc.PC = @intCast(start);
    // std.debug.print("{s}\n", .{mc});

    while (!mc.stopped) {
        // std.debug.print("{s}\n", .{mc});
        mc.step();
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

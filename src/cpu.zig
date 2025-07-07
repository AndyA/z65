const std = @import("std");

pub const PanicTrapHandler = struct {
    pub const Self = @This();
    pub fn trap(self: Self, cpu: anytype, opcode: u8) void {
        _ = self;
        std.debug.print("Illegal instruction {x} at {x}\n", .{ opcode, cpu.PC });
        @panic("Illegal instruction");
    }
};

pub const NullInterruptSource = struct {
    pub const Self = @This();

    pub fn poll_irq(self: Self) bool {
        _ = self;
        return false; // No IRQ
    }

    pub fn poll_nmi(self: Self) bool {
        _ = self;
        return false; // No NMI
    }

    pub fn ack_nmi(self: *Self) void {
        _ = self; // No NMI to clear
    }
};

fn splitSpace(spec: []const u8) struct { []const u8, []const u8 } {
    const space = std.mem.indexOfScalar(u8, spec, ' ') orelse return error.InvalidOpcode;
    return .{ spec[0..space], spec[space + 1 ..] };
}

pub fn makeCPU(
    comptime InstructionSet: type,
    comptime AddressModes: type,
    comptime Instructions: type,
    comptime Memory: type,
    comptime InterruptSource: type,
    comptime TrapHandler: type,
) type {
    const constants = @import("constants.zig");

    comptime {
        @setEvalBranchQuota(4000);
        var despatch: [0x100]fn (cpu: anytype) void = undefined;
        var legal: [0x100]bool = @splat(false);
        // Fill the depatch table with illegal instruction handlers
        for (despatch, 0..) |_, opcode| {
            const shim = struct {
                pub fn instr(cpu: anytype) void {
                    cpu.trap_handler.trap(cpu, opcode);
                }
            };
            despatch[opcode] = shim.instr;
        }

        switch (@typeInfo(InstructionSet)) {
            .@"enum" => |en| {
                for (en.fields) |field| {
                    const spec = field.name;
                    const opcode = field.value;
                    if (legal[opcode])
                        @compileError("Duplicate opcode: " ++ spec);
                    legal[opcode] = true;
                    if (std.mem.indexOfScalar(u8, spec, ' ')) |space| {
                        const mnemonic = spec[0..space];
                        const addr_mode = spec[space + 1 ..];
                        const inst_fn = @field(Instructions, mnemonic);
                        const addr_fn = @field(AddressModes, addr_mode);
                        const shim = struct {
                            pub fn instr(cpu: anytype) void {
                                inst_fn(cpu, addr_fn(cpu));
                            }
                        };
                        despatch[opcode] = shim.instr;
                    } else {
                        despatch[opcode] = @field(Instructions, spec);
                    }
                }
            },
            else => @compileError("InstructionSet must be an enum type"),
        }

        return struct {
            const Self = @This();
            const STACK = constants.STACK;
            const IRQV = constants.IRQV;
            const RESETV = constants.RESETV;
            const NMIV = constants.NMIV;
            const PSR = @import("status_reg.zig").PSR;

            mem: Memory,
            int_source: InterruptSource,
            trap_handler: TrapHandler,
            stopped: bool = false,
            A: u8 = 0,
            X: u8 = 0,
            Y: u8 = 0,
            S: u8 = 0xff,
            P: PSR = PSR{},
            PC: u16 = 0,

            pub fn init(mem: Memory, int_source: InterruptSource, trap_handler: TrapHandler) Self {
                return Self{
                    .mem = mem,
                    .int_source = int_source,
                    .trap_handler = trap_handler,
                };
            }

            pub fn peek8(self: *Self, addr: u16) u8 {
                return self.mem.peek8(addr);
            }

            pub fn poke8(self: *Self, addr: u16, value: u8) void {
                self.mem.poke8(addr, value);
            }

            pub fn peek16(self: *Self, addr: u16) u16 {
                const lo: u16 = self.peek8(addr);
                const hi: u16 = self.peek8(addr +% 1);
                return (hi << 8) | lo;
            }

            pub fn poke16(self: *Self, addr: u16, value: u16) void {
                self.poke8(addr, @intCast(value & 0x00FF));
                self.poke8(addr +% 1, @intCast((value >> 8) & 0x00FF));
            }

            pub fn fetch8(self: *Self) u8 {
                const byte = self.peek8(self.PC);
                self.PC +%= 1;
                return byte;
            }

            pub fn asm8(self: *Self, byte: u8) void {
                self.poke8(self.PC, byte);
                self.PC +%= 1;
            }

            pub fn fetch16(self: *Self) u16 {
                const lo: u16 = self.fetch8();
                const hi: u16 = self.fetch8();
                return (hi << 8) | lo;
            }

            pub fn asm16(self: *Self, value: u16) void {
                self.poke8(self.PC, @intCast(value & 0x00FF));
                self.poke8(self.PC +% 1, @intCast((value >> 8) & 0x00FF));
                self.PC +%= 2;
            }

            pub fn pop8(self: *Self) u8 {
                self.S +%= 1;
                return self.peek8(STACK | self.S);
            }

            pub fn push8(self: *Self, byte: u8) void {
                self.poke8(STACK | self.S, byte);
                self.S -%= 1;
            }

            pub fn pop16(self: *Self) u16 {
                const lo: u16 = self.pop8();
                const hi: u16 = self.pop8();
                return (hi << 8) | lo;
            }

            pub fn push16(self: *Self, value: u16) void {
                self.push8(@intCast((value >> 8) & 0x00FF));
                self.push8(@intCast(value & 0x00FF));
            }

            pub fn is_legal(opcode: u8) bool {
                return legal[opcode];
            }

            fn interrupt(self: *Self, vector: u16) void {
                self.push16(self.PC);
                self.push8(self.P.value());
                self.PC = self.peek16(vector);
                self.P.I = true; // Set interrupt disable
            }

            pub fn handleIrq(self: *Self) void {
                self.interrupt(IRQV);
                self.P.B = false;
            }

            pub fn handleNmi(self: *Self) void {
                self.interrupt(NMIV);
            }

            pub fn reset(self: *Self) void {
                self.PC = self.peek16(RESETV);
                self.P.I = true; // Set interrupt disable
            }

            fn handleInterrupts(self: *Self) void {
                if (self.int_source.poll_nmi()) {
                    self.int_source.ack_nmi();
                    self.handleNmi();
                } else if (!self.P.I and self.int_source.poll_irq()) {
                    self.handleIrq();
                }
            }

            pub fn step(self: *Self) void {
                self.handleInterrupts();
                switch (self.fetch8()) {
                    inline 0...despatch.len - 1 => |op| despatch[op](self),
                }
            }

            pub fn stop(self: *Self) void {
                self.stopped = true;
            }

            pub fn format(
                self: Self,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                _ = options;
                try writer.print(
                    \\PC: {x:0>4} P: {s} A: {x:0>2} X: {x:0>2} Y: {x:0>2} S: {x:0>2}
                , .{ self.PC, self.P, self.A, self.X, self.Y, self.S });
            }

            pub fn asmi(self: *Self, instr: InstructionSet) void {
                const opcode: u8 = @intFromEnum(instr);
                self.asm8(opcode);
            }

            pub fn asmi8(self: *Self, instr: InstructionSet, byte: u8) void {
                const opcode: u8 = @intFromEnum(instr);
                self.asm8(opcode);
                self.asm8(byte);
            }

            pub fn asmi16(self: *Self, instr: InstructionSet, word: u16) void {
                const opcode: u8 = @intFromEnum(instr);
                self.asm8(opcode);
                self.asm16(word);
            }
        };
    }
}

test "cpu" {
    const expect = @import("std").testing.expect;
    const memory = @import("memory.zig");

    var ram: [0x10000]u8 = @splat(0);

    const M6502 = makeCPU(
        @import("mos6502.zig").InstructionSet6502,
        @import("address_modes.zig").AddressModes,
        @import("instructions.zig").Instructions,
        memory.FlatMemory,
        NullInterruptSource,
        PanicTrapHandler,
    );

    var mc = M6502.init(
        memory.FlatMemory{ .ram = &ram },
        NullInterruptSource{},
        PanicTrapHandler{},
    );

    // stack stuff
    mc.poke8(0x1ff, 0xaa); // Test stack wrap
    mc.poke8(0x100, 0x5a); // Test stack wrap
    try expect(mc.peek8(0x1ff) == 0xaa);
    mc.push8(0x55);
    try expect(mc.peek8(0x1ff) == 0x55);
    try expect(mc.S == 0xfe);
    try expect(mc.pop8() == 0x55);
    try expect(mc.S == 0xff);
    try expect(mc.pop8() == 0x5a);
    try expect(mc.S == 0x00);
    mc.push8(0xa5);
    try expect(mc.S == 0xff);
    try expect(mc.peek8(0x100) == 0xa5);
}

test "trap" {
    const expect = @import("std").testing.expect;
    const memory = @import("memory.zig");
    const TRAP_OPCODE: u8 = 0xA7; // Illegal opcode

    const TestTrapHandler = struct {
        trapped: [256]usize = @splat(0),
        pub const Self = @This();
        pub fn trap(self: *Self, cpu: anytype, opcode: u8) void {
            if (opcode == TRAP_OPCODE) {
                const signal: u8 = cpu.fetch8();
                self.trapped[signal] += 1;
            } else {
                @panic("Illegal instruction");
            }
        }
    };

    var ram: [0x10000]u8 = @splat(0);

    const M6502 = makeCPU(
        @import("mos6502.zig").InstructionSet6502,
        @import("address_modes.zig").AddressModes,
        @import("instructions.zig").Instructions,
        memory.FlatMemory,
        NullInterruptSource,
        TestTrapHandler,
    );

    var mc = M6502.init(
        memory.FlatMemory{ .ram = &ram },
        NullInterruptSource{},
        TestTrapHandler{},
    );

    try expect(!M6502.is_legal(TRAP_OPCODE));

    mc.PC = 0x8000;
    mc.poke16(M6502.RESETV, mc.PC);
    mc.asm8(TRAP_OPCODE);
    mc.asm8(0x01);
    mc.asm8(TRAP_OPCODE);
    mc.asm8(0x11);

    mc.reset();
    mc.step();
    try expect(mc.trap_handler.trapped[0x01] == 1);
    try expect(mc.trap_handler.trapped[0x11] == 0);
    mc.step();
    try expect(mc.trap_handler.trapped[0x01] == 1);
    try expect(mc.trap_handler.trapped[0x11] == 1);
}

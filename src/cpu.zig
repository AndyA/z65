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

pub fn makeCPU(
    comptime opcodes: [256][]const u8,
    comptime AddressModes: type,
    comptime Instructions: type,
    comptime Memory: type,
    comptime InterruptSource: type,
    comptime TrapHandler: type,
) type {
    const constants = @import("constants.zig");
    const STACK = constants.STACK;
    const IRQV = constants.IRQV;
    const RESETV = constants.RESETV;
    const NMIV = constants.NMIV;
    const PSR = @import("status_reg.zig").PSR;

    comptime {
        @setEvalBranchQuota(4000);
        var despatch: [opcodes.len]fn (cpu: anytype) void = undefined;

        for (opcodes, 0..) |spec, opcode| {
            const space = std.mem.indexOfScalar(u8, spec, ' ') orelse @compileError("bad opcode");
            const mnemonic = spec[0..space];
            const addr_mode = spec[space + 1 ..];
            if (std.mem.eql(u8, addr_mode, "ill")) {
                const shim = struct {
                    pub fn instr(cpu: anytype) void {
                        cpu.trap_handler.trap(cpu, opcode);
                    }
                };
                despatch[opcode] = shim.instr;
            } else if (@hasDecl(AddressModes, addr_mode)) {
                const addr_fn = @field(AddressModes, addr_mode);
                const inst_fn = @field(Instructions, mnemonic);
                const shim = struct {
                    pub fn instr(cpu: anytype) void {
                        const ea = addr_fn(cpu);
                        inst_fn(cpu, ea);
                    }
                };
                despatch[opcode] = shim.instr;
            } else {
                despatch[opcode] = @field(Instructions, mnemonic);
            }
        }

        return struct {
            mem: Memory,
            int_source: InterruptSource,
            trap_handler: TrapHandler,
            A: u8 = 0,
            X: u8 = 0,
            Y: u8 = 0,
            S: u8 = 0xff,
            P: PSR = PSR{},
            PC: u16 = 0,

            const Self = @This();

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
                const lo: u16 = @intCast(self.peek8(addr));
                const hi: u16 = @intCast(self.peek8(addr +% 1));
                return (hi << 8) | lo;
            }

            pub fn poke16(self: *Self, addr: u16, value: u16) void {
                self.poke8(addr, @intCast(value & 0x00FF));
                self.poke8(addr +% 1, @intCast((value >> 8) & 0x00FF));
            }

            pub fn fetch8(self: *Self) u8 {
                const byte = self.peek8(self.PC);
                // std.debug.print("{x:0>4}: {x:0>2}\n", .{ self.PC, byte });
                self.PC +%= 1;
                return byte;
            }

            pub fn asm8(self: *Self, byte: u8) void {
                self.poke8(self.PC, byte);
                self.PC +%= 1;
            }

            pub fn asm16(self: *Self, value: u16) void {
                self.poke8(self.PC, @intCast(value & 0x00FF));
                self.poke8(self.PC +% 1, @intCast((value >> 8) & 0x00FF));
                self.PC +%= 2;
            }

            pub fn fetch16(self: *Self) u16 {
                const lo: u16 = @intCast(self.fetch8());
                const hi: u16 = @intCast(self.fetch8());
                return (hi << 8) | lo;
            }

            pub fn push8(self: *Self, byte: u8) void {
                self.poke8(STACK | self.S, byte);
                self.S -%= 1;
            }

            pub fn pop8(self: *Self) u8 {
                self.S +%= 1;
                return self.peek8(STACK | self.S);
            }

            pub fn push16(self: *Self, value: u16) void {
                self.push8(@intCast((value >> 8) & 0x00FF));
                self.push8(@intCast(value & 0x00FF));
            }

            pub fn pop16(self: *Self) u16 {
                const lo: u16 = @intCast(self.pop8());
                const hi: u16 = @intCast(self.pop8());
                return (hi << 8) | lo;
            }

            fn interrupt(self: *Self, vector: u16) void {
                self.push16(self.PC);
                self.push8(self.P.value());
                self.PC = self.peek16(vector);
                self.P.I = true; // Set interrupt disable
            }

            pub fn handle_irq(self: *Self) void {
                self.interrupt(IRQV);
                self.P.B = false;
            }

            pub fn handle_nmi(self: *Self) void {
                self.interrupt(NMIV);
            }

            pub fn reset(self: *Self) void {
                self.PC = self.mem.fetch16(RESETV);
                self.P.I = true; // Set interrupt disable
            }

            pub fn step(self: *Self) void {
                if (self.int_source.poll_nmi()) {
                    self.int_source.ack_nmi();
                    self.handle_nmi();
                } else if (!self.P.I and self.int_source.poll_irq()) {
                    self.handle_irq();
                }
                const opcode = self.fetch8();
                switch (opcode) {
                    inline 0...opcodes.len - 1 => |op| {
                        const instruction = despatch[op];
                        instruction(self);
                    },
                }
            }

            pub fn format(
                self: Self,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                _ = options;
                const args = .{ self.PC, self.P, self.A, self.X, self.Y, self.S };
                try writer.print("PC: {x:0>4} P: {s} A: {x:0>2} X: {x:0>2} Y: {x:0>2} S: {x:0>2}", args);
            }
        };
    }
}

test "cpu" {
    const expect = @import("std").testing.expect;
    const memory = @import("memory.zig");

    var ram: [0x10000]u8 = @splat(0);

    const M6502 = makeCPU(
        @import("mos6502.zig").INSTRUCTION_SET,
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
        @import("mos6502.zig").INSTRUCTION_SET,
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

    mc.PC = 0x8000;
    mc.asm8(TRAP_OPCODE);
    mc.asm8(0x01);
    mc.asm8(TRAP_OPCODE);
    mc.asm8(0x11);
    mc.PC = 0x8000;

    mc.step();
    try expect(mc.trap_handler.trapped[0x01] == 1);
    try expect(mc.trap_handler.trapped[0x11] == 0);
    mc.step();
    try expect(mc.trap_handler.trapped[0x01] == 1);
    try expect(mc.trap_handler.trapped[0x11] == 1);
}

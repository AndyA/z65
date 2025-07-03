const std = @import("std");

pub fn make6502(
    comptime AddressModes: type,
    comptime Instructions: type,
    comptime Memory: type,
    comptime InterruptSource: type,
    comptime opcodes: [256][]const u8,
) type {
    const constants = @import("constants.zig");
    const STACK = constants.STACK;
    const IRQV = constants.IRQV;
    const RESETV = constants.RESETV;
    const NMIV = constants.NMIV;
    const PSR = @import("status_reg.zig").PSR;

    comptime {
        var despatch: [256]fn (cpu: anytype) void = undefined;

        for (opcodes, 0..) |spec, opcode| {
            const space = std.mem.indexOfScalar(u8, spec, ' ') orelse @compileError("bad opcode");
            const mnemonic = spec[0..space];
            const addr_mode = spec[space + 1 ..];
            if (std.mem.eql(u8, addr_mode, "ill")) {
                const shim = struct {
                    pub fn instr(cpu: anytype) void {
                        std.debug.print("Illegal instruction {x} at {x}\n", .{ opcode, cpu.PC });
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
            A: u8 = 0,
            X: u8 = 0,
            Y: u8 = 0,
            S: u8 = 0xff,
            P: PSR = PSR{},
            PC: u16 = 0,

            const Self = @This();

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
                    inline 0x00...0xff => |op| {
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
                try writer.print("PC: {x:0>4} P: {s} A: {x:0>2} X: {x:0>2} Y: {x:0>2} S: {x:0>2}", .{
                    self.PC,
                    self.P,
                    self.A,
                    self.X,
                    self.Y,
                    self.S,
                });
            }
        };
    }
}

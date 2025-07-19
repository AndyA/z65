const std = @import("std");
const serde = @import("../serde.zig").serde;
const ct = @import("../cpu/cpu_tools.zig");
const constants = @import("constants.zig");

const TRAP_OPCODE: u8 = 0xBB;

pub const MOSFunction = constants.MOSFunction;
pub const MOSEntry = constants.MOSEntry;
pub const MOSVectors = constants.MOSVectors;
pub const Symbols = constants.Symbols;

const OSFILE = @import("osfile.zig").OSFILE;
const OSCLI = @import("oscli.zig").OSCLI;

const RW_u40 = serde(u40);
const RW_OSFILE = serde(OSFILE);

pub fn TubeOS(comptime LangType: type) type {
    return struct {
        const Self = @This();
        base_time_ms: i64,
        alloc: std.mem.Allocator,
        reader: *std.io.Reader,
        writer: *std.io.Writer,
        lang: *LangType,

        pub fn init(
            alloc: std.mem.Allocator,
            reader: *std.io.Reader,
            writer: *std.io.Writer,
            lang: *LangType,
        ) !Self {
            return Self{
                .base_time_ms = std.time.milliTimestamp(),
                .alloc = alloc,
                .reader = reader,
                .writer = writer,
                .lang = lang,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn installInHost(self: Self, cpu: anytype) void {
            _ = self;
            const STUB_START: u16 = 0xffce;
            const IRQV: u16 = 0xfffe;

            cpu.PC = 0xff00; // traps
            // Build traps and populate vectors
            switch (@typeInfo(MOSFunction)) {
                .@"enum" => |info| {
                    inline for (info.fields) |field| {
                        const vec_name = field.name[2..] ++ "V";
                        const vec_addr: u16 = @intFromEnum(@field(MOSVectors, vec_name));
                        const trap_addr = cpu.PC;
                        cpu.asm8(TRAP_OPCODE);
                        cpu.asm8(@intCast(field.value));
                        cpu.asmi(.RTS);
                        cpu.poke16(vec_addr, trap_addr);
                    }
                },
                else => @panic("Invalid MOSFunction type"),
            }

            const irq_addr = cpu.PC;

            // IRQ
            cpu.asmi8(.@"STA zpg", 0xFC);
            cpu.asmi(.PLA);
            cpu.asmi(.PHA);
            cpu.asmi8(.@"AND #", 0x10);
            cpu.asmi8(.@"BNE rel", 5);
            cpu.asmi8(.@"LDA zpg", 0xFC);
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.IRQV));

            // BRK
            cpu.asmi(.PHX);
            cpu.asmi(.TSX);
            cpu.asmi8(.@"STX zpg", 0xF0);
            cpu.asmi16(.@"LDA abs, X", 0x0103);
            cpu.asmi(.SEC);
            cpu.asmi8(.@"SBC #", 0x01);
            cpu.asmi8(.@"STA zpg", 0xFD);
            cpu.asmi16(.@"LDA abs, X", 0x0104);
            cpu.asmi8(.@"SBC #", 0x00);
            cpu.asmi8(.@"STA zpg", 0xFE);
            cpu.asmi(.PLX);
            cpu.asmi8(.@"LDA zpg", 0xFC);
            cpu.asmi(.CLI);
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BRKV));

            std.debug.assert(cpu.PC <= STUB_START);

            cpu.PC = STUB_START;
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.FINDV));
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.GBPBV));
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BPUTV));
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BGETV));
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.ARGSV));
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.FILEV));
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.RDCHV));
            std.debug.assert(cpu.PC == 0xffe3);
            cpu.asmi8(.@"CMP #", 0x0d); // OSASCI
            cpu.asmi8(.@"BNE rel", 0x07); // 7 bytes to LFFEE
            cpu.asmi8(.@"LDA #", 0x0a); // OSNEWL
            cpu.asmi16(.@"JSR abs", 0xffee);
            cpu.asmi8(.@"LDA #", 0x0d);
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.WRCHV));
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.WORDV));
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BYTEV));
            cpu.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.CLIV));
            std.debug.assert(cpu.PC == 0xfffa);
            cpu.poke16(IRQV, irq_addr);
        }

        fn sendLine(self: *Self, cpu: anytype, addr: u16, ln: []const u8) void {
            _ = self;
            const buf_addr = cpu.peek16(addr);
            const max_len = cpu.peek8(addr + 2);
            cpu.Y = @as(u8, @min(ln.len, max_len));
            cpu.P.C = false;
            ct.pokeBytes(cpu, buf_addr, ln);
            cpu.poke8(@intCast(buf_addr + ln.len), 0x0D); // CR-terminate}
        }

        pub fn trap(self: *Self, cpu: anytype, opcode: u8) void {
            if (opcode == TRAP_OPCODE) {
                const osfn: MOSFunction = @enumFromInt(cpu.fetch8());
                switch (osfn) {
                    .OSCLI => {
                        var cmd_line = ct.peekString(self.alloc, cpu, ct.getXY(cpu), 0x0D) catch
                            unreachable;
                        defer cmd_line.deinit();
                        const res = OSCLI.handle(cmd_line.items, cpu) catch |err| {
                            std.debug.print("Error: {s}\n", .{@errorName(err)});
                            return;
                        };
                        if (!res)
                            std.debug.print("Bad command {s}\n", .{cmd_line.items});
                    },
                    .OSBYTE => {
                        switch (cpu.A) {
                            0x7e => {
                                cpu.X = cpu.peek8(0xff) & 0x80;
                                cpu.poke8(0xff, 0x00); // clear Escape
                            },
                            0x82 => ct.setXY(cpu, @intFromEnum(Symbols.MACHINE)),
                            0x83 => ct.setXY(cpu, @intFromEnum(Symbols.PAGE)),
                            0x84 => ct.setXY(cpu, @intFromEnum(Symbols.HIMEM)),
                            0xda => {}, // set VDU queue length
                            else => std.debug.print(
                                \\OSBYTE {x} not implemented {f}
                                \\
                            , .{ cpu.A, cpu }),
                        }
                    },
                    .OSWORD => {
                        const addr = ct.getXY(cpu);
                        switch (cpu.A) {
                            0x00 => {
                                if (@hasDecl(LangType, "hook:readline")) {
                                    const line = self.lang.@"hook:readline"(self, cpu) catch |err| {
                                        std.debug.print("Error in hook:readline: {s}\n", .{@errorName(err)});
                                        @panic("hook:readline failed");
                                    };
                                    if (line) |ln| {
                                        self.sendLine(cpu, addr, ln);
                                        return;
                                    }
                                }

                                const ln = self.reader.takeDelimiterExclusive('\n') catch |err| {
                                    switch (err) {
                                        error.EndOfStream => {
                                            cpu.stop();
                                            return;
                                        },
                                        else => unreachable,
                                    }
                                };
                                self.sendLine(cpu, addr, ln);
                            },
                            0x01 => {
                                const delta_ms = std.time.milliTimestamp() - self.base_time_ms;
                                const delta_cs: u40 = @intCast(@divTrunc(delta_ms, 10));
                                RW_u40.write(cpu, addr, delta_cs);
                            },
                            0x02 => {
                                const new_time_cs = RW_u40.read(cpu, addr);
                                self.base_time_ms = std.time.milliTimestamp() - new_time_cs * 10;
                            },
                            else => std.debug.print("OSWORD {x} not implemented\n", .{cpu.A}),
                        }
                    },
                    .OSWRCH => {
                        self.writer.print("{c}", .{cpu.A}) catch |err| {
                            std.debug.print("Error writing character: {s}\n", .{@errorName(err)});
                        };
                    },
                    .OSRDCH => {
                        std.debug.print("OSRDCH {f}\n", .{cpu});
                    },
                    .OSFILE => {
                        const cb: OSFILE = RW_OSFILE.read(cpu, ct.getXY(cpu));
                        cb.despatch(self.alloc, cpu) catch |err| {
                            std.debug.print("Error in OSFILE: {s}\n", .{@errorName(err)});
                        };
                    },
                    .OSARGS => {
                        std.debug.print("OSARGS {f}\n", .{cpu});
                    },
                    .OSBGET => {
                        std.debug.print("OSBGET {f}\n", .{cpu});
                    },
                    .OSBPUT => {
                        std.debug.print("OSBPUT {f}\n", .{cpu});
                    },
                    .OSGBPB => {
                        std.debug.print("OSGBPB {f}\n", .{cpu});
                    },
                    .OSFIND => {
                        std.debug.print("OSFIND {f}\n", .{cpu});
                    },
                }
            } else {
                std.debug.print("Illegal instruction: {x} at {f}\n", .{ opcode, cpu });
                @panic("Illegal instruction");
            }
        }
    };
}

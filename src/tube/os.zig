const std = @import("std");
const serde = @import("../tools/serde.zig").serde;
const ct = @import("../tools/cpu_tools.zig");
const constants = @import("constants.zig");
const vdu = @import("vdu.zig");

const TRAP_OPCODE: u8 = 0xBB;

pub const MOSFunction = constants.MOSFunction;
pub const MOSEntry = constants.MOSEntry;
pub const MOSVectors = constants.MOSVectors;
pub const Symbols = constants.Symbols;

const OSFILE = @import("osfile.zig").OSFILE;
const OSCLI = @import("oscli.zig").OSCLI;

const RW_u40 = serde(u40);
const RW_OSFILE = serde(OSFILE);

// TODO VDUType
pub fn TubeOS(comptime LangType: type) type {
    return struct {
        const Self = @This();
        base_time_ms: i64,
        alloc: std.mem.Allocator,
        reader: *std.io.Reader,
        writer: *std.io.Writer,
        lang: *LangType,
        vdu: vdu.VDU,

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
                .vdu = vdu.VDU.init(writer),
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn reset(self: Self, cpu: anytype) void {
            self.install(cpu);
        }

        fn install(self: Self, cpu: anytype) void {
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

        pub fn @"hook:ifetch"(self: *Self, cpu: anytype, addr: u16, byte: u8) void {
            if (@hasDecl(LangType, "hook:ifetch")) {
                self.lang.@"hook:fetch"(cpu, addr, byte);
            }
        }

        pub fn @"hook:fetch"(self: *Self, cpu: anytype, addr: u16, byte: u8) void {
            if (@hasDecl(LangType, "hook:fetch")) {
                self.lang.@"hook:fetch"(cpu, addr, byte);
            }
        }

        pub fn @"hook:read"(self: *Self, cpu: anytype, addr: u16, byte: u8) void {
            if (@hasDecl(LangType, "hook:read")) {
                self.lang.@"hook:read"(cpu, addr, byte);
            }
        }

        pub fn @"hook:write"(self: *Self, cpu: anytype, addr: u16, byte: u8) void {
            if (@hasDecl(LangType, "hook:write")) {
                self.lang.@"hook:write"(cpu, addr, byte);
            }
        }

        pub fn hexDump(self: Self, cpu: anytype, start: u16, end: u16) !void {
            var pos = start;
            var buf: [16]u8 = undefined;
            while (pos < end) : (pos += 16) {
                var avail = @min(16, end - pos);
                const bytes = buf[0..avail];
                ct.peekBytes(cpu, pos, bytes);
                try self.writer.print("{x:0>4} |", .{pos});
                for (bytes) |byte|
                    try self.writer.print(" {x:0>2}", .{byte});
                while (avail < 16) : (avail += 1)
                    try self.writer.print("   ", .{});
                try self.writer.print(" | ", .{});
                for (bytes) |byte| {
                    const rep = if (std.ascii.isPrint(byte)) byte else '.';
                    try self.writer.print("{c}", .{rep});
                }
                try self.writer.print("\n", .{});
            }
        }

        fn raiseError(self: *Self, cpu: anytype, code: u8, msg: []const u8) void {
            const err_buf: u16 = @intFromEnum(Symbols.OS_BASE);
            cpu.poke8(err_buf + 0, 0x00);
            cpu.poke8(err_buf + 1, code);
            ct.pokeString(cpu, err_buf + 2, msg, 0x0d);
            cpu.PC = err_buf + 0;
            _ = self;
        }

        fn sendBuffer(self: *Self, cpu: anytype, addr: u16, ln: []const u8) void {
            _ = self;
            const buf_addr = cpu.peek16(addr);
            const max_len = cpu.peek8(addr + 2);
            cpu.Y = @as(u8, @min(ln.len, max_len));
            cpu.P.C = false;
            ct.pokeString(cpu, buf_addr, ln, 0x0D);
        }

        fn sendLine(self: *Self, cpu: anytype, addr: u16, ln: []const u8) !void {
            if (@hasDecl(LangType, "hook:sendline")) {
                const replaced = try self.lang.@"hook:sendline"(cpu, ln);
                self.sendBuffer(cpu, addr, replaced);
            } else {
                self.sendBuffer(cpu, addr, ln);
            }
        }

        fn doOSCLI(self: *Self, cpu: anytype) !void {
            var cmd_line = try ct.peekString(self.alloc, cpu, ct.getXY(cpu), 0x0D);
            defer cmd_line.deinit();
            var res = try OSCLI.handle(cmd_line.items, cpu);

            if (@hasDecl(LangType, "hook:oscli")) {
                if (!res) res = try self.lang.@"hook:oscli"(cmd_line.items, cpu);
            }

            if (!res)
                self.raiseError(cpu, 254, "Bad command");
        }

        fn doOSBYTE(self: *Self, cpu: anytype) !void {
            _ = self;
            switch (cpu.A) {
                0x7e => {
                    cpu.X = cpu.peek8(0xff) & 0x80;
                    cpu.poke8(0xff, 0x00); // clear Escape
                },
                0x82 => ct.setXY(cpu, @intFromEnum(Symbols.MACHINE)),
                0x83 => ct.setXY(cpu, @intFromEnum(Symbols.PAGE)),
                0x84 => ct.setXY(cpu, @intFromEnum(Symbols.HIMEM)),
                0xda => {}, // set VDU queue length
                else => std.debug.print("OSBYTE {x} not implemented {f}\n", .{ cpu.A, cpu }),
            }
        }

        fn doOSWORD(self: *Self, cpu: anytype) !void {
            const addr = ct.getXY(cpu);
            switch (cpu.A) {
                0x00 => {
                    if (@hasDecl(LangType, "hook:readline")) {
                        const line = try self.lang.@"hook:readline"(cpu);
                        if (line) |ln| {
                            try self.sendLine(cpu, addr, ln);
                            return;
                        }
                    }

                    const ln = self.reader.takeDelimiterExclusive('\n') catch |err| {
                        switch (err) {
                            error.EndOfStream => {
                                cpu.stop();
                                return;
                            },
                            else => return err,
                        }
                    };
                    try self.sendLine(cpu, addr, ln);
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
        }

        fn doOSFILE(self: *Self, cpu: anytype) !void {
            const cb: OSFILE = RW_OSFILE.read(cpu, ct.getXY(cpu));
            try cb.despatch(self.alloc, cpu);
        }

        fn doOSWRCH(self: *Self, cpu: anytype) !void {
            // try self.writer.print("{c}", .{cpu.A});
            try self.vdu.oswrch(cpu.A);
        }

        fn doOSRDCH(self: *Self, cpu: anytype) !void {
            _ = self;
            std.debug.print("OSRDCH {f}\n", .{cpu});
        }

        fn doOSARGS(self: *Self, cpu: anytype) !void {
            _ = self;
            std.debug.print("OSARGS {f}\n", .{cpu});
        }

        fn doOSBGET(self: *Self, cpu: anytype) !void {
            _ = self;
            std.debug.print("OSBGET {f}\n", .{cpu});
        }

        fn doOSBPUT(self: *Self, cpu: anytype) !void {
            _ = self;
            std.debug.print("OSBPUT {f}\n", .{cpu});
        }

        fn doOSGBPB(self: *Self, cpu: anytype) !void {
            _ = self;
            std.debug.print("OSGBPB {f}\n", .{cpu});
        }

        fn doOSFIND(self: *Self, cpu: anytype) !void {
            _ = self;
            std.debug.print("OSFIND {f}\n", .{cpu});
        }

        pub fn trap(self: *Self, cpu: anytype, opcode: u8) !void {
            if (opcode == TRAP_OPCODE) {
                const osfn: MOSFunction = @enumFromInt(cpu.fetch8());
                switch (osfn) {
                    .OSCLI => try self.doOSCLI(cpu),
                    .OSBYTE => try self.doOSBYTE(cpu),
                    .OSWORD => try self.doOSWORD(cpu),
                    .OSWRCH => try self.doOSWRCH(cpu),
                    .OSRDCH => try self.doOSRDCH(cpu),
                    .OSFILE => try self.doOSFILE(cpu),
                    .OSARGS => try self.doOSARGS(cpu),
                    .OSBGET => try self.doOSBGET(cpu),
                    .OSBPUT => try self.doOSBPUT(cpu),
                    .OSGBPB => try self.doOSGBPB(cpu),
                    .OSFIND => try self.doOSFIND(cpu),
                }
            } else {
                std.debug.print("Illegal instruction: {x} at {f}\n", .{ opcode, cpu });
                @panic("Illegal instruction");
            }
        }
    };
}

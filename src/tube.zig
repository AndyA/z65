const std = @import("std");
const ct = @import("cpu_tools.zig");
const serde = @import("serde.zig").serde;
const oscli = @import("oscli.zig");

const TRAP_OPCODE: u8 = 0xBB;

const MOSFunction = enum(u8) {
    OSCLI = 1, // OSCLI
    OSBYTE,
    OSWORD,
    OSWRCH, // Write character
    OSRDCH, // Read character
    OSFILE,
    OSARGS,
    OSBGET,
    OSBPUT,
    OSGBPB, // Get Block, Put Block
    OSFIND, // Open file
};

pub const MOSEntry = enum(u16) {
    OSCLI = 0xFFF7,
    OSBYTE = 0xFFF4,
    OSWORD = 0xFFF1,
    OSWRCH = 0xFFEE,
    OSNEWL = 0xFFE7,
    OSASCI = 0xFFE3,
    OSRDCH = 0xFFE0,
    OSFILE = 0xFFDD,
    OSARGS = 0xFFDA,
    OSBGET = 0xFFD7,
    OSBPUT = 0xFFD4,
    OSGBPB = 0xFFD1,
    OSFIND = 0xFFCE,
};

pub const MOSVectors = enum(u16) {
    BRKV = 0x0202,
    IRQV = 0x0204,
    CLIV = 0x0208,
    BYTEV = 0x020A,
    WORDV = 0x020C,
    WRCHV = 0x020E,
    RDCHV = 0x0210,
    FILEV = 0x0212,
    ARGSV = 0x0214,
    BGETV = 0x0216,
    BPUTV = 0x0218,
    GBPBV = 0x021A,
    FINDV = 0x021C,
};

pub const Symbols = enum(u16) {
    PAGE = 0x800,
    HIMEM = 0xb800,
    MACHINE = 0x0000,
};

pub const OSFILE_CB = struct {
    const Self = @This();

    filename: u16,
    load_addr: u32,
    exec_addr: u32,
    start_addr: u32,
    end_addr: u32,

    pub fn format(self: Self, writer: std.io.Writer) std.io.Writer.Error!void {
        try writer.print(
            \\filename: {x:0>4} load: {x:0>8} exec: {x:0>8} start: {x:0>8} end: {x:0>8}
        , .{ self.filename, self.load_addr, self.exec_addr, self.start_addr, self.end_addr });
    }

    fn save(self: Self, alloc: std.mem.Allocator, cpu: anytype) !u8 {
        var file_name = try ct.peekString(alloc, cpu, self.filename, 0x0D);
        defer file_name.deinit();

        const size: u16 = @intCast(self.end_addr - self.start_addr);
        const bytes = try ct.peekBytesAlloc(alloc, cpu, @intCast(self.start_addr), size);
        defer alloc.free(bytes);

        // std.debug.print("Saving {s} \"{s}\"\n", .{ self, file_name.items });

        const file = try std.fs.cwd().createFile(file_name.items, .{ .truncate = true });
        defer file.close();

        try file.writeAll(bytes);
        return 0x01;
    }

    fn load(self: Self, alloc: std.mem.Allocator, cpu: anytype) !u8 {
        var file_name = try ct.peekString(alloc, cpu, self.filename, 0x0D);
        defer file_name.deinit();

        const file = try std.fs.cwd().openFile(file_name.items, .{});
        defer file.close();

        var buffer: [1024]u8 = undefined;
        var offset: u16 = 0;

        // std.debug.print("Loading {s} \"{s}\"\n", .{ self, file_name.items });

        while (true) {
            const read_size = try file.read(&buffer);
            if (read_size == 0) break; // EOF
            ct.pokeBytes(cpu, @intCast(self.load_addr + offset), buffer[0..read_size]);
            offset += @intCast(read_size);
        }
        return 0x01;
    }

    pub fn despatch(self: Self, alloc: std.mem.Allocator, cpu: anytype) !void {
        switch (cpu.A) {
            0x00 => cpu.A = try self.save(alloc, cpu),
            0xFF => cpu.A = try self.load(alloc, cpu),
            else => std.debug.print("Unknown OSFILE operation: {x}\n", .{cpu.A}),
        }
    }
};

const StarCommands = struct {
    pub fn @"*CAT"(cpu: anytype, args: anytype) !void {
        _ = cpu;
        _ = args;
        std.debug.print("Meow!\n", .{});
    }

    pub fn @"*FX <A:u8> [,<X:u8> [,<Y:u8>]]"(cpu: anytype, args: anytype) !void {
        cpu.A = args.A;
        cpu.X = args.X orelse 0;
        cpu.Y = args.Y orelse 0;
        cpu.PC = @intFromEnum(MOSEntry.OSBYTE);
    }

    pub fn @"*SAVE <name:[]u8> <start:u16x> <end:u16xr> [<exec:u16x>]"(
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = cpu;
        std.debug.print("*SAVE \"{s}\" {x} {x}\n", .{
            args.name,
            args.start,
            args.end.resolve(args.start),
        });
    }

    pub fn @"*LOAD <name:[]u8> [<start:u16x>]"(
        cpu: anytype,
        args: anytype,
    ) !void {
        _ = cpu;
        std.debug.print("*LOAD \"{s}\" {x}\n", .{
            args.name,
            args.start orelse 0x800,
        });
    }

    pub fn @"*!<shell:[]u8*>"(cpu: anytype, args: anytype) !void {
        _ = cpu;
        std.debug.print("shell {s}\n", .{args.shell});
    }
};

const OSCLI = oscli.makeHandler(StarCommands);

const RW_u40 = serde(u40);
const RW_OSFILE = serde(OSFILE_CB);

pub const TubeOS = struct {
    const Self = @This();
    base_time_ms: i64,
    alloc: std.mem.Allocator,
    reader: *std.io.Reader,
    writer: *std.io.Writer,

    pub fn init(
        alloc: std.mem.Allocator,
        reader: *std.io.Reader,
        writer: *std.io.Writer,
    ) !Self {
        try writer.print("TubeOS initialized\n", .{});
        return Self{
            .base_time_ms = std.time.milliTimestamp(),
            .alloc = alloc,
            .reader = reader,
            .writer = writer,
        };
    }

    pub fn installInHost(cpu: anytype) void {
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
                        else => std.debug.print("OSBYTE {x} not implemented {f}\n", .{ cpu.A, cpu }),
                    }
                },
                .OSWORD => {
                    const addr = ct.getXY(cpu);
                    switch (cpu.A) {
                        0x00 => {
                            const ln = self.reader.takeDelimiterExclusive('\n') catch |err| {
                                switch (err) {
                                    error.EndOfStream => {
                                        std.debug.print("\nBye!\n", .{});
                                        cpu.stop();
                                        return;
                                    },
                                    else => unreachable,
                                }
                            };
                            const buf_addr = cpu.peek16(addr);
                            const max_len = cpu.peek8(addr + 2);
                            cpu.Y = @as(u8, @min(ln.len, max_len));
                            cpu.P.C = false;
                            ct.pokeBytes(cpu, buf_addr, ln);
                            cpu.poke8(@intCast(buf_addr + ln.len), 0x0D); // CR-terminate
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
                    const cb: OSFILE_CB = RW_OSFILE.read(cpu, ct.getXY(cpu));
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

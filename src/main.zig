const std = @import("std");
const machine = @import("cpu.zig");
const memory = @import("memory.zig");
const tt = @import("type_tools.zig");
const srec = @import("srec.zig");

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

const MOSVectors = enum(u16) {
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

const PAGE = 0x800;
const HIMEM = 0xb800;
const MACHINE = 0x0000;
const TRACE = 0xfe90;

fn setXY(cpu: anytype, xy: u16) void {
    cpu.X = @intCast(xy & 0xff);
    cpu.Y = @intCast(xy >> 8);
}

fn getXY(cpu: anytype) u16 {
    return @as(u16, cpu.Y) << 8 | @as(u16, cpu.X);
}

fn pokeBytes(cpu: anytype, addr: u16, bytes: []const u8) void {
    for (bytes, 0..) |byte, i| {
        const offset: u16 = @intCast(i);
        cpu.poke8(addr + offset, byte);
    }
}

fn peekBytes(cpu: anytype, addr: u16, bytes: []u8) void {
    for (0..bytes.len) |i| {
        const offset: u16 = @intCast(i);
        bytes[i] = cpu.peek8(addr + offset);
    }
}

fn peekBytesAlloc(alloc: std.mem.Allocator, cpu: anytype, addr: u16, size: usize) ![]u8 {
    var buf = try alloc.alloc(u8, size);
    errdefer alloc.free(buf);

    for (0..size) |i| {
        buf[i] = cpu.peek8(@intCast(addr + i));
    }

    return buf;
}

fn peekString(alloc: std.mem.Allocator, cpu: anytype, addr: u16, sentinel: u8) !std.ArrayList(u8) {
    var buf = try std.ArrayList(u8).initCapacity(alloc, 256);
    errdefer buf.deinit();

    var offset: u16 = 0;
    while (true) {
        const byte = cpu.peek8(@intCast(addr + offset));
        if (byte == sentinel) break;
        try buf.append(byte);
        offset += 1;
    }

    return buf;
}

fn furnace(comptime T: type) type {
    comptime {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                var furnaces: [info.fields.len]type = undefined;
                var bytes = 0;
                for (info.fields, 0..) |field, i| {
                    furnaces[i] = furnace(field.type);
                    bytes += furnaces[i].byteSize;
                }

                return struct {
                    pub const bytesSize = bytes;
                    const f = furnaces;

                    pub fn read(cpu: anytype, addr: u16) T {
                        var ret: T = undefined;
                        var offset: u16 = 0;
                        inline for (info.fields, 0..) |field, i| {
                            @field(ret, field.name) = f[i].read(cpu, addr + offset);
                            offset += f[i].byteSize;
                        }
                        return ret;
                    }

                    pub fn write(cpu: anytype, addr: u16, value: T) void {
                        var offset: u16 = 0;
                        inline for (info.fields, 0..) |field, i| {
                            f[i].write(cpu, addr + offset, @field(value, field.name));
                            offset += f[i].byteSize;
                        }
                    }
                };
            },
            .int => |info| {
                if (info.bits & 0x03 != 0) {
                    @compileError("Furnace can only be used with multiples of 8 bits");
                }

                return struct {
                    pub const byteSize = @divFloor(info.bits, 8);

                    pub fn read(cpu: anytype, addr: u16) T {
                        var raw_value: [byteSize]u8 = undefined;
                        peekBytes(cpu, addr, &raw_value);
                        return std.mem.littleToNative(T, @bitCast(raw_value));
                    }

                    pub fn write(cpu: anytype, addr: u16, value: T) void {
                        const raw_value: [byteSize]u8 = @bitCast(std.mem.nativeToLittle(T, value));
                        pokeBytes(cpu, addr, &raw_value);
                    }
                };
            },
            else => @compileError("Furnace can only be used with structs or integers"),
        }
    }
}

const OSFILE_CB = struct {
    const Self = @This();

    filename: u16,
    load_addr: u32,
    exec_addr: u32,
    start_addr: u32,
    end_addr: u32,

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        opt: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print(
            \\filename: {x:0>4} load: {x:0>8} exec: {x:0>8} start: {x:0>8} end: {x:0>8}
        , .{ self.filename, self.load_addr, self.exec_addr, self.start_addr, self.end_addr });
        _ = fmt;
        _ = opt;
    }

    fn save(self: Self, alloc: std.mem.Allocator, cpu: anytype) !void {
        var file_name = try peekString(alloc, cpu, self.filename, 0x0D);
        defer file_name.deinit();

        const size: u16 = @intCast(self.end_addr - self.start_addr);
        const bytes = try peekBytesAlloc(alloc, cpu, @intCast(self.start_addr), size);
        defer alloc.free(bytes);

        // std.debug.print("Saving {s} \"{s}\"\n", .{ self, file_name.items });

        const file = try std.fs.cwd().createFile(file_name.items, .{ .truncate = true });
        defer file.close();
        try file.writeAll(bytes);
        cpu.A = 0x01;
    }

    fn load(self: Self, alloc: std.mem.Allocator, cpu: anytype) !void {
        var file_name = try peekString(alloc, cpu, self.filename, 0x0D);
        defer file_name.deinit();

        const file = try std.fs.cwd().openFile(file_name.items, .{});
        defer file.close();

        var buffer: [1024]u8 = undefined;
        var offset: u16 = 0;

        // std.debug.print("Loading {s} \"{s}\"\n", .{ self, file_name.items });

        while (true) {
            const read_size = try file.read(&buffer);
            if (read_size == 0) break; // EOF
            pokeBytes(cpu, @intCast(self.load_addr + offset), buffer[0..read_size]);
            offset += @intCast(read_size);
        }
        cpu.A = 0x01;
    }

    pub fn despatch(self: Self, alloc: std.mem.Allocator, cpu: anytype) !void {
        switch (cpu.A) {
            0x00 => try self.save(alloc, cpu),
            0xFF => try self.load(alloc, cpu),
            else => std.debug.print("Unknown OSFILE operation: {x}\n", .{cpu.A}),
        }
    }
};

const F_u40 = furnace(u40);
const F_OSFILE = furnace(OSFILE_CB);

const TubeTrapHandler = struct {
    const Self = @This();
    base_time_ms: i64,
    alloc: std.mem.Allocator,

    pub fn trap(self: *Self, cpu: anytype, opcode: u8) void {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn().reader();

        if (opcode == TRAP_OPCODE) {
            const osfn: MOSFunction = @enumFromInt(cpu.fetch8());
            switch (osfn) {
                .OSCLI => {
                    std.debug.print("OSCLI {s}\n", .{cpu});
                },
                .OSBYTE => {
                    switch (cpu.A) {
                        0x82 => setXY(cpu, MACHINE),
                        0x83 => setXY(cpu, PAGE),
                        0x84 => setXY(cpu, HIMEM),
                        else => std.debug.print("OSBYTE {x} not implemented {s}\n", .{ cpu.A, cpu }),
                    }
                },
                .OSWORD => {
                    const addr = getXY(cpu);
                    switch (cpu.A) {
                        0x00 => {
                            var buf: [256]u8 = undefined;
                            const res = stdin.readUntilDelimiterOrEof(&buf, '\n') catch unreachable;
                            if (res) |ln| {
                                const buf_addr = cpu.peek16(addr);
                                const max_len = cpu.peek8(addr + 2);
                                cpu.Y = @as(u8, @min(ln.len, max_len));
                                cpu.P.C = false;
                                pokeBytes(cpu, buf_addr, ln);
                                cpu.poke8(@intCast(buf_addr + ln.len), 0x0D); // null-terminate
                            } else {
                                std.debug.print("\nBye!\n", .{});
                                cpu.stop();
                            }
                        },
                        0x01 => {
                            const delta_ms = std.time.milliTimestamp() - self.base_time_ms;
                            const delta_cs: u40 = @intCast(@divTrunc(delta_ms, 10));
                            F_u40.write(cpu, addr, delta_cs);
                        },
                        0x02 => {
                            const new_time_cs = F_u40.read(cpu, addr);
                            self.base_time_ms = std.time.milliTimestamp() - new_time_cs * 10;
                        },
                        else => std.debug.print("OSWORD {x} not implemented\n", .{cpu.A}),
                    }
                },
                .OSWRCH => {
                    stdout.print("{c}", .{cpu.A}) catch unreachable;
                },
                .OSRDCH => {
                    std.debug.print("OSRDCH {s}\n", .{cpu});
                },
                .OSFILE => {
                    const cb: OSFILE_CB = F_OSFILE.read(cpu, getXY(cpu));
                    cb.despatch(self.alloc, cpu) catch |err| {
                        std.debug.print("Error in OSFILE: {s}\n", .{@errorName(err)});
                    };
                },
                .OSARGS => {
                    std.debug.print("OSARGS {s}\n", .{cpu});
                },
                .OSBGET => {
                    std.debug.print("OSBGET {s}\n", .{cpu});
                },
                .OSBPUT => {
                    std.debug.print("OSBPUT {s}\n", .{cpu});
                },
                .OSGBPB => {
                    std.debug.print("OSGBPB {s}\n", .{cpu});
                },
                .OSFIND => {
                    std.debug.print("OSFIND {s}\n", .{cpu});
                },
            }
        } else {
            std.debug.print("Illegal instruction: {x} at {s}\n", .{ opcode, cpu });
            @panic("Illegal instruction");
        }
    }
};

const Tube65C02 = machine.makeCPU(
    @import("wdc65c02.zig").InstructionSet65C02,
    @import("address_modes.zig").AddressModes,
    @import("instructions.zig").Instructions,
    @import("alu.zig").ALU65C02,
    memory.FlatMemory,
    machine.NullInterruptSource,
    TubeTrapHandler,
    .{ .clear_decimal_on_int = true },
);

fn buildTubeOS(mc: *Tube65C02) void {
    mc.PC = 0xff00; // traps
    const STUB_START = 0xffca;

    // Build traps and populate vectors
    switch (@typeInfo(MOSFunction)) {
        .@"enum" => |info| {
            inline for (info.fields) |field| {
                const vec_name = field.name[2..] ++ "V";
                const vec_addr: u16 = @intFromEnum(@field(MOSVectors, vec_name));
                const trap_addr = mc.PC;
                mc.asm8(TRAP_OPCODE);
                mc.asm8(@intCast(field.value));
                mc.asmi(.RTS);
                mc.poke16(vec_addr, trap_addr);
            }
        },
        else => @panic("Invalid MOSFunction type"),
    }

    std.debug.assert(mc.PC <= STUB_START);
    mc.PC = STUB_START;
    const irq_addr = mc.PC;
    mc.asmi(.CLI);
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BRKV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.FINDV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.GBPBV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BPUTV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BGETV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.ARGSV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.FILEV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.RDCHV));
    std.debug.assert(mc.PC == 0xffe3);
    mc.asmi8(.@"CMP #", 0x0d);
    mc.asmi8(.@"BNE rel", 0x07); // 7 bytes to LFFEE
    mc.asmi8(.@"LDA #", 0x0a);
    mc.asmi16(.@"JSR abs", 0xffee);
    mc.asmi8(.@"LDA #", 0x0d);
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.WRCHV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.WORDV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.BYTEV));
    mc.asmi16(.@"JMP (abs)", @intFromEnum(MOSVectors.CLIV));
    std.debug.assert(mc.PC == 0xfffa);
    mc.poke16(Tube65C02.IRQV, irq_addr);
}

const HI_BASIC = @embedFile("roms/HiBASIC.rom");

pub fn main() !void {
    var ram: [0x10000]u8 = @splat(0);
    @memcpy(ram[HIMEM .. HIMEM + HI_BASIC.len], HI_BASIC);

    var trapper = TubeTrapHandler{
        .base_time_ms = std.time.milliTimestamp(),
        .alloc = std.heap.page_allocator,
    };

    var mc = Tube65C02.init(
        memory.FlatMemory{ .ram = &ram },
        machine.NullInterruptSource{},
        &trapper,
    );

    buildTubeOS(&mc);

    mc.PC = @intCast(HIMEM);
    mc.A = 0x01;
    mc.poke8(TRACE, 0x00); // disable tracing

    while (!mc.stopped) {
        mc.step();
        switch (mc.peek8(TRACE)) {
            0x00 => {},
            0x01 => std.debug.print("{s!j}\n", .{mc}),
            0x02 => std.debug.print("{s}\n", .{mc}),
            else => {},
        }
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

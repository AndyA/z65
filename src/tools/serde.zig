const std = @import("std");
const ct = @import("cpu_tools.zig");

pub fn serdeEx(comptime T: type, comptime big_endian: bool) type {
    comptime {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                var serdes: [info.fields.len]type = undefined;
                var bytes = 0;
                for (info.fields, 0..) |field, i| {
                    serdes[i] = serdeEx(field.type, big_endian);
                    bytes += serdes[i].byteSize;
                }

                return struct {
                    pub const BaseType = T;
                    pub const byteSize: usize = bytes;
                    const fields = serdes;

                    pub fn read(cpu: anytype, addr: u16) T {
                        var ret: T = undefined;
                        var offset: u16 = 0;
                        inline for (info.fields, 0..) |field, i| {
                            @field(ret, field.name) = fields[i].read(cpu, addr + offset);
                            offset += fields[i].byteSize;
                        }
                        return ret;
                    }

                    pub fn write(cpu: anytype, addr: u16, value: T) void {
                        var offset: u16 = 0;
                        inline for (info.fields, 0..) |field, i| {
                            fields[i].write(cpu, addr + offset, @field(value, field.name));
                            offset += fields[i].byteSize;
                        }
                    }
                };
            },
            .array => |info| {
                const child = serdeEx(info.child, big_endian);

                return struct {
                    pub const BaseType = T;
                    pub const byteSize: usize = child.byteSize * info.len;

                    pub fn read(cpu: anytype, addr: u16) T {
                        var value: T = undefined;
                        var offset: u16 = 0;
                        for (0..info.len) |i| {
                            value[i] = child.read(cpu, addr + offset);
                            offset += child.byteSize;
                        }
                        return value;
                    }

                    pub fn write(cpu: anytype, addr: u16, value: T) void {
                        var offset: u16 = 0;
                        for (0..info.len) |i| {
                            child.write(cpu, addr + offset, value[i]);
                            offset += child.byteSize;
                        }
                    }
                };
            },
            .int => |info| {
                if (info.bits & 0x03 != 0) {
                    @compileError("SerDe can only be used with multiples of 8 bits");
                }

                return struct {
                    pub const BaseType = T;
                    pub const byteSize: usize = @divFloor(info.bits, 8);

                    pub fn read(cpu: anytype, addr: u16) T {
                        var raw_value: [byteSize]u8 = undefined;
                        ct.peekBytes(cpu, addr, &raw_value);
                        if (big_endian) {
                            return std.mem.bigToNative(T, @bitCast(raw_value));
                        } else {
                            return std.mem.littleToNative(T, @bitCast(raw_value));
                        }
                    }

                    pub fn write(cpu: anytype, addr: u16, value: T) void {
                        if (big_endian) {
                            const raw_value: [byteSize]u8 = @bitCast(std.mem.nativeToBig(T, value));
                            ct.pokeBytes(cpu, addr, &raw_value);
                        } else {
                            const raw_value: [byteSize]u8 = @bitCast(std.mem.nativeToLittle(T, value));
                            ct.pokeBytes(cpu, addr, &raw_value);
                        }
                    }
                };
            },
            else => @compileError("SerDe can only be used with structs or integers"),
        }
    }
}

pub fn serde(comptime T: type) type {
    return serdeEx(T, false);
}

pub fn serdeBigEndian(comptime T: type) type {
    return serdeEx(T, true);
}

const std = @import("std");
const ct = @import("cpu/cpu_tools.zig");

pub fn serde(comptime T: type) type {
    comptime {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                var serdes: [info.fields.len]type = undefined;
                var bytes = 0;
                for (info.fields, 0..) |field, i| {
                    serdes[i] = serde(field.type);
                    bytes += serdes[i].byteSize;
                }

                return struct {
                    pub const bytesSize = bytes;
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
            .int => |info| {
                if (info.bits & 0x03 != 0) {
                    @compileError("SerDe can only be used with multiples of 8 bits");
                }

                return struct {
                    pub const byteSize = @divFloor(info.bits, 8);

                    pub fn read(cpu: anytype, addr: u16) T {
                        var raw_value: [byteSize]u8 = undefined;
                        ct.peekBytes(cpu, addr, &raw_value);
                        return std.mem.littleToNative(T, @bitCast(raw_value));
                    }

                    pub fn write(cpu: anytype, addr: u16, value: T) void {
                        const raw_value: [byteSize]u8 = @bitCast(std.mem.nativeToLittle(T, value));
                        ct.pokeBytes(cpu, addr, &raw_value);
                    }
                };
            },
            else => @compileError("SerDe can only be used with structs or integers"),
        }
    }
}

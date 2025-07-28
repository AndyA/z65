const serde = @import("../../tools/serde.zig");
const ct = @import("../../tools/cpu_tools.zig");

const BasicStringError = error{TooLong};

const BasicString = struct {
    const Self = @This();
    const Serde = serde.serde(Self);

    addr: u16,
    cap: u8,
    len: u8,

    pub fn initFromMemory(mem: anytype, addr: u16) Self {
        return Serde.read(mem, addr);
    }

    pub fn write(self: Self, mem: anytype, addr: u16) void {
        Serde.write(mem, addr, self);
    }

    pub fn getString(self: Self, mem: anytype, buf: []u8) ![]const u8 {
        if (self.addr == 0) return "";
        if (self.len > buf.len) return BasicStringError.TooLong;
        ct.peekBytes(mem, self.addr, buf[0..self.len]);
        return buf[0..self.len];
    }
};

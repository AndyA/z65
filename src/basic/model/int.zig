const serde = @import("../../tools/serde.zig");
const ct = @import("../../tools/cpu_tools.zig");

const BasicInt = struct {
    const Self = @This();
    const Serde = serde.serde(Self);

    int: u32,
    pub fn initFromMemory(mem: anytype, addr: u16) Self {
        return Serde.read(mem, addr);
    }

    pub fn write(self: Self, mem: anytype, addr: u16) void {
        Serde.write(mem, addr, self);
    }
};

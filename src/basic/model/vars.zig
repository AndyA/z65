const constants = @import("../constants.zig");
const string = @import("string.zig");
const fp = @import("fp.zig");
const int = @import("int.zig");

pub const VarType = enum(u8) { Str = 0x00, Int = 0x40, FP = 0xff };
pub const Var = union(VarType) {
    Str: string.BasicString,
    FP: fp.BasicFP64,
    Int: int.BasicInt,
};

pub const VarSlot = struct {
    const Self = @This();
    v: Var,
    m: Model,
};

pub const Model = struct {
    ram: *[]u8,
    const Self = @This();

    pub fn poke8(self: *Self, addr: u16, value: u8) void {
        self.ram[addr] = value;
    }

    pub fn peek8(self: Self, addr: u16) u8 {
        return self.ram[addr];
    }
};

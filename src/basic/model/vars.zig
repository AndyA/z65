const constants = @import("../constants.zig");
const string = @import("string.zig");
const fp = @import("fp.zig");
const int = @import("int.zig");

pub const VarType = enum { Str, FP, Int };
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

pub const Model = struct {};

const constants = @import("../tube/constants.zig");

pub const HIMEM = @intFromEnum(constants.Symbols.HIMEM);
pub const PAGE = @intFromEnum(constants.Symbols.PAGE);
pub const ZP = struct {
    pub const VARTOP = 0x00; // Top of vars
    pub const SP = 0x04; // Basic stack pointer
    pub const HIMEM = 0x06; // current HIMEM
    pub const NEXTP = 0x0b; // current program line pointer
    pub const TOP = 0x12; // current TOP
    pub const PAGE_HI = 0x18;
};

pub const CMD_BUF = 0x700;
pub const VAR_CHAINS = 0x0480;
pub const PROC_CHAIN = 0x04f6;
pub const FN_CHAIN = 0x04f8;

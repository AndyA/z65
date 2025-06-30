pub const STACK: u16 = 0x0100;
pub const IRQV: u16 = 0xfffe;
pub const RESETV: u16 = 0xfffc;
pub const NMIV: u16 = 0xfffa;

pub const C_BIT: u8 = 1 << 0;
pub const Z_BIT: u8 = 1 << 1;
pub const I_BIT: u8 = 1 << 2;
pub const D_BIT: u8 = 1 << 3;
pub const B_BIT: u8 = 1 << 4;
pub const V_BIT: u8 = 1 << 6;
pub const N_BIT: u8 = 1 << 7;

pub const MOSFunction = enum(u8) {
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

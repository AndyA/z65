pub const InstructionSet6502 = enum(u8) {
    // Loads
    @"LDA #" = 0xa9,
    @"LDA (zpg, X)" = 0xa1,
    @"LDA abs" = 0xad,
    @"LDA abs, X" = 0xbd,
    @"LDA abs, Y" = 0xb9,
    @"LDA (zpg), Y" = 0xb1,
    @"LDA zpg" = 0xa5,
    @"LDA zpg, X" = 0xb5,

    @"LDX #" = 0xa2,
    @"LDX abs" = 0xae,
    @"LDX abs, Y" = 0xbe,
    @"LDX zpg" = 0xa6,
    @"LDX zpg, Y" = 0xb6,

    @"LDY #" = 0xa0,
    @"LDY abs" = 0xac,
    @"LDY abs, X" = 0xbc,
    @"LDY zpg" = 0xa4,
    @"LDY zpg, X" = 0xb4,

    // Stores
    @"STA (zpg, X)" = 0x81,
    @"STA abs" = 0x8d,
    @"STA abs, X" = 0x9d,
    @"STA abs, Y" = 0x99,
    @"STA (zpg), Y" = 0x91,
    @"STA zpg" = 0x85,
    @"STA zpg, X" = 0x95,

    @"STX abs" = 0x8e,
    @"STX zpg" = 0x86,
    @"STX zpg, Y" = 0x96,

    @"STY abs" = 0x8c,
    @"STY zpg" = 0x84,
    @"STY zpg, X" = 0x94,

    // Stack
    @"PHA impl" = 0x48,
    @"PLA impl" = 0x68,
    @"PHP impl" = 0x08,
    @"PLP impl" = 0x28,

    // Register transfers
    @"TAX impl" = 0xaa,
    @"TXA impl" = 0x8a,
    @"TAY impl" = 0xa8,
    @"TYA impl" = 0x98,
    @"TSX impl" = 0xba,
    @"TXS impl" = 0x9a,

    // Logic
    @"AND #" = 0x29,
    @"AND (zpg, X)" = 0x21,
    @"AND abs" = 0x2d,
    @"AND abs, X" = 0x3d,
    @"AND abs, Y" = 0x39,
    @"AND (zpg), Y" = 0x31,
    @"AND zpg" = 0x25,
    @"AND zpg, X" = 0x35,

    @"EOR #" = 0x49,
    @"EOR (zpg, X)" = 0x41,
    @"EOR abs" = 0x4d,
    @"EOR abs, X" = 0x5d,
    @"EOR abs, Y" = 0x59,
    @"EOR (zpg), Y" = 0x51,
    @"EOR zpg" = 0x45,
    @"EOR zpg, X" = 0x55,

    @"ORA #" = 0x09,
    @"ORA (zpg, X)" = 0x01,
    @"ORA abs" = 0x0d,
    @"ORA abs, X" = 0x1d,
    @"ORA abs, Y" = 0x19,
    @"ORA (zpg), Y" = 0x11,
    @"ORA zpg" = 0x05,
    @"ORA zpg, X" = 0x15,

    @"BIT abs" = 0x2c,
    @"BIT zpg" = 0x24,

    // Arithmetic
    @"ADC #" = 0x69,
    @"ADC (zpg, X)" = 0x61,
    @"ADC abs" = 0x6d,
    @"ADC abs, X" = 0x7d,
    @"ADC abs, Y" = 0x79,
    @"ADC (zpg), Y" = 0x71,
    @"ADC zpg" = 0x65,
    @"ADC zpg, X" = 0x75,

    @"SBC #" = 0xe9,
    @"SBC (zpg, X)" = 0xe1,
    @"SBC abs" = 0xed,
    @"SBC abs, X" = 0xfd,
    @"SBC abs, Y" = 0xf9,
    @"SBC (zpg), Y" = 0xf1,
    @"SBC zpg" = 0xe5,
    @"SBC zpg, X" = 0xf5,

    // Comparisons
    @"CMP #" = 0xc9,
    @"CMP (zpg, X)" = 0xc1,
    @"CMP abs" = 0xcd,
    @"CMP abs, X" = 0xdd,
    @"CMP abs, Y" = 0xd9,
    @"CMP (zpg), Y" = 0xd1,
    @"CMP zpg" = 0xc5,
    @"CMP zpg, X" = 0xd5,

    @"CPX #" = 0xe0,
    @"CPX abs" = 0xec,
    @"CPX zpg" = 0xe4,

    @"CPY #" = 0xc0,
    @"CPY abs" = 0xcc,
    @"CPY zpg" = 0xc4,

    // Shifts
    @"ASL abs" = 0x0e,
    @"ASL abs, X" = 0x1e,
    @"ASL zpg" = 0x06,
    @"ASL zpg, X" = 0x16,
    @"ASLA impl" = 0x0a,

    @"LSR abs" = 0x4e,
    @"LSR abs, X" = 0x5e,
    @"LSR zpg" = 0x46,
    @"LSR zpg, X" = 0x56,
    @"LSRA impl" = 0x4a,

    @"ROL abs" = 0x2e,
    @"ROL abs, X" = 0x3e,
    @"ROL zpg" = 0x26,
    @"ROL zpg, X" = 0x36,
    @"ROLA impl" = 0x2a,

    @"ROR abs" = 0x6e,
    @"ROR abs, X" = 0x7e,
    @"ROR zpg" = 0x66,
    @"ROR zpg, X" = 0x76,
    @"RORA impl" = 0x6a,

    // Increment/Decrement
    @"DEC abs" = 0xce,
    @"DEC abs, X" = 0xde,
    @"DEC zpg" = 0xc6,
    @"DEC zpg, X" = 0xd6,

    @"INC abs" = 0xee,
    @"INC abs, X" = 0xfe,
    @"INC zpg" = 0xe6,
    @"INC zpg, X" = 0xf6,

    @"DEX impl" = 0xca,
    @"DEY impl" = 0x88,
    @"INX impl" = 0xe8,
    @"INY impl" = 0xc8,

    // Flags
    @"CLC impl" = 0x18,
    @"SEC impl" = 0x38,
    @"CLI impl" = 0x58,
    @"SEI impl" = 0x78,
    @"CLV impl" = 0xb8,
    @"CLD impl" = 0xd8,
    @"SED impl" = 0xf8,

    // Branches
    @"BPL rel" = 0x10,
    @"BMI rel" = 0x30,
    @"BVC rel" = 0x50,
    @"BVS rel" = 0x70,
    @"BCC rel" = 0x90,
    @"BCS rel" = 0xb0,
    @"BNE rel" = 0xd0,
    @"BEQ rel" = 0xf0,

    // Jumps and returns
    @"JSR abs" = 0x20,
    @"JMP abs" = 0x4c,
    @"JMP ind*" = 0x6c,
    @"RTS impl" = 0x60,

    // Interrupts
    @"BRK impl" = 0x00,
    @"RTI impl" = 0x40,

    // NOP
    @"NOP impl" = 0xea,
};

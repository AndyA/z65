const Extra65C02 = enum(u8) {
    @"ADC (zpg)" = 0x72,
    @"AND (zpg)" = 0x32,
    @"CMP (zpg)" = 0xD2,
    @"EOR (zpg)" = 0x52,
    @"LDA (zpg)" = 0xB2,
    @"ORA (zpg)" = 0x12,
    @"SBC (zpg)" = 0xF2,
    @"STA (zpg)" = 0x92,

    @"BITA #" = 0x89, // is this actually BITA?
    @"BIT zpg, X" = 0x34,
    @"BIT abs, X" = 0x3C,

    DECA = 0x3A,
    INCA = 0x1A,

    PHX = 0xDA,
    PHY = 0x5A,
    PLX = 0xFA,
    PLY = 0x7A,

    @"STZ zpg" = 0x64,
    @"STZ zpg, X" = 0x74,
    @"STZ abs" = 0x9C,
    @"STZ abs, X" = 0x9E,

    @"TRB zpg" = 0x14,
    @"TRB abs" = 0x1C,

    @"TSB zpg" = 0x04,
    @"TSB abs" = 0x0C,

    @"BRA rel" = 0x80,

    @"BBR0 zpg, rel" = 0x0F,
    @"BBR1 zpg, rel" = 0x1F,
    @"BBR2 zpg, rel" = 0x2F,
    @"BBR3 zpg, rel" = 0x3F,
    @"BBR4 zpg, rel" = 0x4F,
    @"BBR5 zpg, rel" = 0x5F,
    @"BBR6 zpg, rel" = 0x6F,
    @"BBR7 zpg, rel" = 0x7F,

    @"BBS0 zpg, rel" = 0x8F,
    @"BBS1 zpg, rel" = 0x9F,
    @"BBS2 zpg, rel" = 0xAF,
    @"BBS3 zpg, rel" = 0xBF,
    @"BBS4 zpg, rel" = 0xCF,
    @"BBS5 zpg, rel" = 0xDF,
    @"BBS6 zpg, rel" = 0xEF,
    @"BBS7 zpg, rel" = 0xFF,

    @"RMB0 zpg" = 0x07,
    @"RMB1 zpg" = 0x17,
    @"RMB2 zpg" = 0x27,
    @"RMB3 zpg" = 0x37,
    @"RMB4 zpg" = 0x47,
    @"RMB5 zpg" = 0x57,
    @"RMB6 zpg" = 0x67,
    @"RMB7 zpg" = 0x77,

    @"SMB0 zpg" = 0x87,
    @"SMB1 zpg" = 0x97,
    @"SMB2 zpg" = 0xA7,
    @"SMB3 zpg" = 0xB7,
    @"SMB4 zpg" = 0xC7,
    @"SMB5 zpg" = 0xD7,
    @"SMB6 zpg" = 0xE7,
    @"SMB7 zpg" = 0xF7,

    @"JMP (abs)" = 0x6c,
    @"JMP (abs, X)" = 0x7c,

    STP = 0xDB,
    WAI = 0xCB,
};

const tt = @import("type_tools.zig");

pub const InstructionSet65C02 = tt.mergeInstructionSets(
    @import("mos6502.zig").InstructionSet6502,
    Extra65C02,
);

test "6502 functional test" {
    const test_code = @embedFile("test/data/6502_functional_test.s19");
    const ft = @import("functional_test.zig");
    // Test with a 6502 ALU because otherwise decimal mode will fail
    try ft.runFunctionalTest(
        InstructionSet65C02,
        @import("alu.zig").ALU6502,
        .{ .clear_decimal_on_int = true },
        test_code,
    );
}

test "65C02 functional test" {
    const test_code = @embedFile("test/data/65C02_extended_opcodes_test.s19");
    const ft = @import("functional_test.zig");
    try ft.runFunctionalTest(
        InstructionSet65C02,
        @import("alu.zig").ALU65C02,
        .{ .clear_decimal_on_int = true },
        test_code,
    );
}

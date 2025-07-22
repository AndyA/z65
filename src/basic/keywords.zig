const std = @import("std");

pub const Keyword = struct { name: []const u8, flags: u8 };

fn KW(name: []const u8, flags: u8) Keyword {
    return Keyword{ .name = name, .flags = flags };
}

pub const basicKeywords = [0x80]?Keyword{
    KW("AND", 0x00),
    KW("DIV", 0x00),
    KW("EOR", 0x00),
    KW("MOD", 0x00),
    KW("OR", 0x00),
    KW("ERROR", 0x04),
    KW("LINE", 0x00),
    KW("OFF", 0x00),
    KW("STEP", 0x00),
    KW("SPC", 0x00),
    KW("TAB(", 0x00),
    KW("ELSE", 0x14),
    KW("THEN", 0x14),
    KW(":line:", 0xff),
    KW("OPENIN", 0x00),
    KW("PTR", 0x43),
    KW("PAGE", 0x43),
    KW("TIME", 0x43),
    KW("LOMEM", 0x43),
    KW("HIMEM", 0x43),
    KW("ABS", 0x00),
    KW("ACS", 0x00),
    KW("ADVAL", 0x00),
    KW("ASC", 0x00),
    KW("ASN", 0x00),
    KW("ATN", 0x00),
    KW("BGET", 0x01),
    KW("COS", 0x00),
    KW("COUNT", 0x01),
    KW("DEG", 0x00),
    KW("ERL", 0x01),
    KW("ERR", 0x01),
    KW("EVAL", 0x00),
    KW("EXP", 0x00),
    KW("EXT", 0x01),
    KW("FALSE", 0x01),
    KW("FN", 0x08),
    KW("GET", 0x00),
    KW("INKEY", 0x00),
    KW("INSTR(", 0x00),
    KW("INT", 0x00),
    KW("LEN", 0x00),
    KW("LN", 0x00),
    KW("LOG", 0x00),
    KW("NOT", 0x00),
    KW("OPENUP", 0x00),
    KW("OPENOUT", 0x00),
    KW("PI", 0x01),
    KW("POINT(", 0x00),
    KW("POS", 0x01),
    KW("RAD", 0x00),
    KW("RND", 0x01),
    KW("SGN", 0x00),
    KW("SIN", 0x00),
    KW("SQR", 0x00),
    KW("TAN", 0x00),
    KW("TO", 0x00),
    KW("TRUE", 0x01),
    KW("USR", 0x00),
    KW("VAL", 0x00),
    KW("VPOS", 0x01),
    KW("CHR$", 0x00),
    KW("GET$", 0x00),
    KW("INKEY$", 0x00),
    KW("LEFT$(", 0x00),
    KW("MID$(", 0x00),
    KW("RIGHT$(", 0x00),
    KW("STR$", 0x00),
    KW("STRING$(", 0x00),
    KW("EOF", 0x01),
    KW("AUTO", 0x10),
    KW("DELETE", 0x10),
    KW("LOAD", 0x02),
    KW("LIST", 0x10),
    KW("NEW", 0x01),
    KW("OLD", 0x01),
    KW("RENUMBER", 0x10),
    KW("SAVE", 0x02),
    null,
    KW("PTR=", 0x00),
    KW("PAGE=", 0x00),
    KW("TIME=", 0x00),
    KW("LOMEM=", 0x00),
    KW("HIMEM=", 0x00),
    KW("SOUND", 0x02),
    KW("BPUT", 0x03),
    KW("CALL", 0x02),
    KW("CHAIN", 0x02),
    KW("CLEAR", 0x01),
    KW("CLOSE", 0x03),
    KW("CLG", 0x01),
    KW("CLS", 0x01),
    KW("DATA", 0x20),
    KW("DEF", 0x00),
    KW("DIM", 0x02),
    KW("DRAW", 0x02),
    KW("END", 0x01),
    KW("ENDPROC", 0x01),
    KW("ENVELOPE", 0x02),
    KW("FOR", 0x02),
    KW("GOSUB", 0x12),
    KW("GOTO", 0x12),
    KW("GCOL", 0x02),
    KW("IF", 0x02),
    KW("INPUT", 0x02),
    KW("LET", 0x04),
    KW("LOCAL", 0x02),
    KW("MODE", 0x02),
    KW("MOVE", 0x02),
    KW("NEXT", 0x02),
    KW("ON", 0x02),
    KW("VDU", 0x02),
    KW("PLOT", 0x02),
    KW("PRINT", 0x02),
    KW("PROC", 0x0a),
    KW("READ", 0x02),
    KW("REM", 0x20),
    KW("REPEAT", 0x00),
    KW("REPORT", 0x01),
    KW("RESTORE", 0x12),
    KW("RETURN", 0x01),
    KW("RUN", 0x01),
    KW("STOP", 0x01),
    KW("COLOUR", 0x02),
    KW("TRACE", 0x12),
    KW("UNTIL", 0x02),
    KW("WIDTH", 0x02),
    KW("OSCLI", 0x02),
};

const EnumField = std.builtin.Type.EnumField;

fn makeEnumField(comptime name: []const u8, comptime opcode: u8) EnumField {
    var z_name: [name.len:0]u8 = @splat(' ');
    @memcpy(&z_name, name);
    return .{
        .name = &z_name,
        .value = opcode,
    };
}

fn makeKeywordsEnum() type {
    comptime {
        var used: usize = 0;
        for (basicKeywords) |def| {
            if (def != null) used += 1;
        }

        var fields: [used]EnumField = undefined;
        var index: usize = 0;
        for (basicKeywords, 0..) |kw, rel_token| {
            if (kw) |k| {
                fields[index] = makeEnumField(k.name, @as(u8, rel_token + 0x80));
                index += 1;
            }
        }

        std.debug.assert(index == used);

        return @Type(.{
            .@"enum" = .{
                .tag_type = u8,
                .fields = &fields,
                .decls = &[_]std.builtin.Type.Declaration{},
                .is_exhaustive = false,
            },
        });
    }
}

pub const KeywordsEnum = makeKeywordsEnum();

pub const KeywordsError = error{BadToken};

pub fn getKeyword(token: u8) ?Keyword {
    if (token < 0x80) return null;
    return basicKeywords[token - 0x80];
}

test getKeyword {
    const kw = getKeyword(@intFromEnum(KeywordsEnum.GOTO));
    try std.testing.expect(kw.?.flags == 0x12);
}

pub fn makeFlagCheck(comptime flags: u8) fn (u8) bool {
    const shim = struct {
        pub fn check(token: u8) bool {
            const kw = getKeyword(token);
            if (kw) |k| {
                if (k.flags == flags) return true;
            }
            return false;
        }
    };
    return shim.check;
}

const GOTO_FLAGS = getKeyword(@intFromEnum(KeywordsEnum.GOTO)).?.flags;
const LIST_FLAGS = getKeyword(@intFromEnum(KeywordsEnum.LIST)).?.flags;
const REM_FLAGS = getKeyword(@intFromEnum(KeywordsEnum.REM)).?.flags;

pub const isGotoLike = makeFlagCheck(GOTO_FLAGS);
pub const isListLike = makeFlagCheck(LIST_FLAGS);
pub const isRemLike = makeFlagCheck(REM_FLAGS);

test makeFlagCheck {
    try std.testing.expect(isGotoLike(@intFromEnum(KeywordsEnum.GOTO)));
    try std.testing.expect(isGotoLike(@intFromEnum(KeywordsEnum.GOSUB)));
    try std.testing.expect(!isGotoLike(@intFromEnum(KeywordsEnum.RETURN)));
    try std.testing.expect(isListLike(@intFromEnum(KeywordsEnum.LIST)));
    try std.testing.expect(isListLike(@intFromEnum(KeywordsEnum.RENUMBER)));
    try std.testing.expect(!isListLike(@intFromEnum(KeywordsEnum.GOTO)));
    try std.testing.expect(isRemLike(@intFromEnum(KeywordsEnum.REM)));
    try std.testing.expect(isRemLike(@intFromEnum(KeywordsEnum.DATA)));
    try std.testing.expect(!isRemLike(@intFromEnum(KeywordsEnum.ENDPROC)));
}

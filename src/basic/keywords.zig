const std = @import("std");

pub const Keyword = struct { name: []const u8, token: u8, flags: u8 };

fn KW(name: []const u8, token: u8, flags: u8) Keyword {
    return Keyword{ .name = name, .token = token, .flags = flags };
}

const main_keywords = [_]Keyword{
    KW("AND", 0x80, 0x00),
    KW("ABS", 0x94, 0x00),
    KW("ACS", 0x95, 0x00),
    KW("ADVAL", 0x96, 0x00),
    KW("ASC", 0x97, 0x00),
    KW("ASN", 0x98, 0x00),
    KW("ATN", 0x99, 0x00),
    KW("AUTO", 0xc6, 0x10),
    KW("BGET", 0x9a, 0x01),
    KW("BPUT", 0xd5, 0x03),
    KW("COLOUR", 0xfb, 0x02),
    KW("CALL", 0xd6, 0x02),
    KW("CHAIN", 0xd7, 0x02),
    KW("CHR$", 0xbd, 0x00),
    KW("CLEAR", 0xd8, 0x01),
    KW("CLOSE", 0xd9, 0x03),
    KW("CLG", 0xda, 0x01),
    KW("CLS", 0xdb, 0x01),
    KW("COS", 0x9b, 0x00),
    KW("COUNT", 0x9c, 0x01),
    KW("COLOR", 0xfb, 0x02),
    KW("DATA", 0xdc, 0x20),
    KW("DEG", 0x9d, 0x00),
    KW("DEF", 0xdd, 0x00),
    KW("DELETE", 0xc7, 0x10),
    KW("DIV", 0x81, 0x00),
    KW("DIM", 0xde, 0x02),
    KW("DRAW", 0xdf, 0x02),
    KW("ENDPROC", 0xe1, 0x01),
    KW("END", 0xe0, 0x01),
    KW("ENVELOPE", 0xe2, 0x02),
    KW("ELSE", 0x8b, 0x14),
    KW("EVAL", 0xa0, 0x00),
    KW("ERL", 0x9e, 0x01),
    KW("ERROR", 0x85, 0x04),
    KW("EOF", 0xc5, 0x01),
    KW("EOR", 0x82, 0x00),
    KW("ERR", 0x9f, 0x01),
    KW("EXP", 0xa1, 0x00),
    KW("EXT", 0xa2, 0x01),
    KW("FOR", 0xe3, 0x02),
    KW("FALSE", 0xa3, 0x01),
    KW("FN", 0xa4, 0x08),
    KW("GOTO", 0xe5, 0x12),
    KW("GET$", 0xbe, 0x00),
    KW("GET", 0xa5, 0x00),
    KW("GOSUB", 0xe4, 0x12),
    KW("GCOL", 0xe6, 0x02),
    KW("HIMEM", 0x93, 0x43),
    KW("INPUT", 0xe8, 0x02),
    KW("IF", 0xe7, 0x02),
    KW("INKEY$", 0xbf, 0x00),
    KW("INKEY", 0xa6, 0x00),
    KW("INT", 0xa8, 0x00),
    KW("INSTR(", 0xa7, 0x00),
    KW("LIST", 0xc9, 0x10),
    KW("LINE", 0x86, 0x00),
    KW("LOAD", 0xc8, 0x02),
    KW("LOMEM", 0x92, 0x43),
    KW("LOCAL", 0xea, 0x02),
    KW("LEFT$(", 0xc0, 0x00),
    KW("LEN", 0xa9, 0x00),
    KW("LET", 0xe9, 0x04),
    KW("LOG", 0xab, 0x00),
    KW("LN", 0xaa, 0x00),
    KW("MID$(", 0xc1, 0x00),
    KW("MODE", 0xeb, 0x02),
    KW("MOD", 0x83, 0x00),
    KW("MOVE", 0xec, 0x02),
    KW("NEXT", 0xed, 0x02),
    KW("NEW", 0xca, 0x01),
    KW("NOT", 0xac, 0x00),
    KW("OLD", 0xcb, 0x01),
    KW("ON", 0xee, 0x02),
    KW("OFF", 0x87, 0x00),
    KW("OR", 0x84, 0x00),
    KW("OPENIN", 0x8e, 0x00),
    KW("OPENOUT", 0xae, 0x00),
    KW("OPENUP", 0xad, 0x00),
    KW("OSCLI", 0xff, 0x02),
    KW("PRINT", 0xf1, 0x02),
    KW("PAGE", 0x90, 0x43),
    KW("PTR", 0x8f, 0x43),
    KW("PI", 0xaf, 0x01),
    KW("PLOT", 0xf0, 0x02),
    KW("POINT(", 0xb0, 0x00),
    KW("PROC", 0xf2, 0x0a),
    KW("POS", 0xb1, 0x01),
    KW("RETURN", 0xf8, 0x01),
    KW("REPEAT", 0xf5, 0x00),
    KW("REPORT", 0xf6, 0x01),
    KW("READ", 0xf3, 0x02),
    KW("REM", 0xf4, 0x20),
    KW("RUN", 0xf9, 0x01),
    KW("RAD", 0xb2, 0x00),
    KW("RESTORE", 0xf7, 0x12),
    KW("RIGHT$(", 0xc2, 0x00),
    KW("RND", 0xb3, 0x01),
    KW("RENUMBER", 0xcc, 0x10),
    KW("STEP", 0x88, 0x00),
    KW("SAVE", 0xcd, 0x02),
    KW("SGN", 0xb4, 0x00),
    KW("SIN", 0xb5, 0x00),
    KW("SQR", 0xb6, 0x00),
    KW("SPC", 0x89, 0x00),
    KW("STR$", 0xc3, 0x00),
    KW("STRING$(", 0xc4, 0x00),
    KW("SOUND", 0xd4, 0x02),
    KW("STOP", 0xfa, 0x01),
    KW("TAN", 0xb7, 0x00),
    KW("THEN", 0x8c, 0x14),
    KW("TO", 0xb8, 0x00),
    KW("TAB(", 0x8a, 0x00),
    KW("TRACE", 0xfc, 0x12),
    KW("TIME", 0x91, 0x43),
    KW("TRUE", 0xb9, 0x01),
    KW("UNTIL", 0xfd, 0x02),
    KW("USR", 0xba, 0x00),
    KW("VDU", 0xef, 0x02),
    KW("VAL", 0xbb, 0x00),
    KW("VPOS", 0xbc, 0x01),
    KW("WIDTH", 0xfe, 0x02),
};

const lvalue_keywords = [_]Keyword{
    KW("PAGE=", 0xd0, 0x00),
    KW("PTR=", 0xcf, 0x00),
    KW("TIME=", 0xd1, 0x00),
    KW("LOMEM=", 0xd2, 0x00),
    KW("HIMEM=", 0xd3, 0x00),
};

const special_keywords = [_]Keyword{
    KW(":line:", 0x8d, 0xff),
};

fn makeKeywordTable(keywords: []const Keyword) KeywordTable {
    var table: KeywordTable = @splat(null);
    for (keywords) |kw| {
        const slot = kw.token - 0x80;
        if (table[slot]) |_| {
            if (std.mem.eql(u8, kw.name, "COLOR")) continue;
            @compileError("Duplicate token: " ++ kw.name);
        }
        table[slot] = kw;
    }
    return table;
}

fn makeEnumField(comptime name: []const u8, comptime opcode: u8) EnumField {
    var z_name: [name.len:0]u8 = @splat(' ');
    @memcpy(&z_name, name);
    return .{
        .name = &z_name,
        .value = opcode,
    };
}

fn makeKeywordsEnum(table: *const KeywordTable) type {
    comptime {
        var used: usize = 0;
        for (table) |def| {
            if (def != null) used += 1;
        }

        var fields: [used]EnumField = undefined;
        var index: usize = 0;
        for (keyword_table, 0..) |kw, rel_token| {
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

pub const KeywordsError = error{BadToken};
const EnumField = std.builtin.Type.EnumField;
const KeywordTable = [0x80]?Keyword;

const real_keywords = main_keywords ++ lvalue_keywords;
const keyword_list = real_keywords ++ special_keywords;
const keyword_table = makeKeywordTable(&keyword_list);
pub const KeywordsEnum = makeKeywordsEnum(&keyword_table);

pub fn getKeyword(token: u8) ?Keyword {
    if (token < 0x80) return null;
    return keyword_table[token - 0x80];
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

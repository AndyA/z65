const std = @import("std");
const kw = @import("keywords.zig");
const constants = @import("../tube/constants.zig");
const Code = @import("code.zig").Code;
const util = @import("../tools/util.zig");

pub const BasicIterError = error{BadProgram};

pub const BasicLine = struct {
    line_number: u16,
    bytes: []const u8,
};

pub const BasicIter = struct {
    const Self = @This();
    const bp = BasicIterError.BadProgram;
    prog: []const u8,
    pos: u16 = 0,

    pub fn init(prog: []const u8) Self {
        return Self{ .prog = prog };
    }

    pub fn next(self: *Self) BasicIterError!?BasicLine {
        if (self.pos + 1 >= self.prog.len or self.prog[self.pos] != 0x0D) return bp;
        if (self.prog[self.pos + 1] == 0xFF) { // end of prog?
            if (self.pos + 2 != self.prog.len) return bp;
            return null;
        }
        if (self.pos + 3 >= self.prog.len) return bp;
        const line_number = util.peek16be(self.prog, self.pos + 1);
        const len = self.prog[self.pos + 3];
        if (len < 5) return bp;
        if (self.pos + len >= self.prog.len) return bp;
        const bytes = self.prog[self.pos + 4 .. self.pos + len];
        self.pos += len;

        return BasicLine{
            .line_number = line_number,
            .bytes = bytes,
        };
    }
};

pub const LineTokenIter = struct {
    const Self = @This();
    line: BasicLine,
    pos: u16 = 0,

    pub fn init(line: BasicLine) Self {
        return Self{ .line = line };
    }

    pub fn next(self: *Self) ?u8 {
        const bytes = self.line.bytes;
        while (true) {
            if (self.pos >= bytes.len)
                return null;

            const tok = bytes[self.pos];
            self.pos += 1;

            if (kw.isRemLike(tok))
                return null;

            if (tok == '"') {
                while (self.pos < bytes.len and bytes[self.pos] != '"')
                    self.pos += 1;
                if (self.pos >= bytes.len)
                    return null;
                self.pos += 1;
                continue;
            }

            if (tok >= 0x80)
                return tok;
        }
    }
};

pub const TokenIter = struct {
    const Self = @This();
    line_iter: BasicIter,
    token_iter: ?LineTokenIter = null,

    pub fn init(prog: []const u8) Self {
        return Self{ .line_iter = BasicIter.init(prog) };
    }

    pub fn next(self: *Self) !?u8 {
        while (true) {
            if (self.token_iter == null) {
                const line = try self.line_iter.next();
                if (line) |l|
                    self.token_iter = LineTokenIter.init(l)
                else
                    return null;
            }

            const tok = self.token_iter.?.next();
            if (tok) |t| return t;
            self.token_iter = null;
        }
    }
};

// test TokenIter {
//     const allocator = std.testing.allocator;
//     const prog =
//         \\   10 PRINT """Hello, World""" : REM Quotes!
//         \\   20 GOTO 10
//         \\
//     ;

//     const bin = try sourceToBinary(allocator, prog);
//     defer bin.deinit();

//     // hexDump(bin.bytes);

//     var ti = TokenIter.init(bin.bytes);
//     try std.testing.expectEqualDeep(@intFromEnum(kw.KeywordsEnum.PRINT), try ti.next());
//     try std.testing.expectEqualDeep(@intFromEnum(kw.KeywordsEnum.GOTO), try ti.next());
//     try std.testing.expectEqualDeep(@intFromEnum(kw.KeywordsEnum.@":line:"), try ti.next());
//     try std.testing.expectEqualDeep(null, try ti.next());
// }

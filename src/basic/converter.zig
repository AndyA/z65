const std = @import("std");
const kw = @import("keywords.zig");
const code = @import("code.zig");
const iters = @import("iters.zig");

pub fn needsLineNumbers(prog: []const u8) !bool {
    var ti = iters.TokenIter.init(prog);
    while (try ti.next()) |tok| {
        if (kw.isGotoLike(tok)) return true;
    }
    return false;
}

test needsLineNumbers {
    const allocator = std.testing.allocator;

    {
        const bin = try code.sourceToBinary(allocator,
            \\   10 PRINT """Hello, World""" : REM Quotes!
            \\   20 DATA Hello, World
            \\   30 RESTORE 20
            \\
        );
        defer bin.deinit();
        try std.testing.expect(try needsLineNumbers(bin.bytes));
    }

    {
        const bin = try code.sourceToBinary(allocator,
            \\   10 PRINT """Hello, World""" : REM Quotes!
            \\   20 DATA Hello, World
            \\
        );
        defer bin.deinit();
        try std.testing.expect(!try needsLineNumbers(bin.bytes));
    }
}

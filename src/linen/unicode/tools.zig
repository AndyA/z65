const std = @import("std");
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const WIDTHS = @import("data/width.zig").WIDTHS;

pub fn countCells(codepoint: u21) u2 {
    comptime {
        assert(WIDTHS.len != 0);
        assert(WIDTHS[0].first == 0);
    }

    // Handle the last value edge case up front
    const last = WIDTHS[WIDTHS.len - 1];
    if (codepoint >= last.first) {
        @branchHint(.unlikely);
        return last.width;
    }

    var low: usize = 0;
    var high: usize = WIDTHS.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (codepoint < WIDTHS[mid].first)
            high = mid
        else if (codepoint < WIDTHS[mid + 1].first)
            return WIDTHS[mid].width
        else
            low = mid + 1;
    }

    unreachable;
}

test countCells {
    try expectEqual(0, countCells(0x000000));
    try expectEqual(1, countCells(0x000041));

    for (WIDTHS, 1..) |w, i| {
        try expectEqual(w.width, countCells(w.first));
        const last = if (i == WIDTHS.len) std.math.maxInt(u21) else WIDTHS[i].first - 1;
        try expectEqual(w.width, countCells(last));
    }
}

pub const PreferWidth = enum { narrow, wide };

pub fn countCellsPrefer(codepoint: u21, prefer: PreferWidth) u2 {
    return switch (countCells(codepoint)) {
        1 | 2 => switch (prefer) {
            .narrow => 1,
            .wide => 2,
        },
        else => |cells| cells,
    };
}

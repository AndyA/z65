const std = @import("std");

const WIDTHS = @import("data/width.zig").WIDTHS;

pub fn countCells(codepoint: u21) u2 {
    var low: usize = 0;
    var high: usize = WIDTHS.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (codepoint < WIDTHS[mid].first)
            high = mid
        else if (mid == WIDTHS.len - 1 or codepoint < WIDTHS[mid + 1].first)
            return WIDTHS[mid].width
        else
            low = mid + 1;
    }
    unreachable;
}

const expectEqual = std.testing.expectEqual;

test {
    try expectEqual(0, countCells(0x000000));
    try expectEqual(1, countCells(0x000041));

    for (WIDTHS, 1..) |w, i| {
        try expectEqual(w.width, countCells(w.first));
        const last = if (i == WIDTHS.len) std.math.maxInt(u21) else WIDTHS[i].first - 1;
        try expectEqual(w.width, countCells(last));
    }
}

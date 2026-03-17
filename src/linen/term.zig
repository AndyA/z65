const builtin = @import("builtin");

pub const Term = switch (builtin.os.tag) {
    .windows => @compileError("Sorry - no Windows support yet"),
    else => @import("linen/platform/POSIX.zig"),
};

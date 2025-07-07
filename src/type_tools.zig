const std = @import("std");

fn collectEnum(comptime T: type, defs: *[256]?[]const u8) void {
    switch (@typeInfo(T)) {
        .@"enum" => |en| {
            for (en.fields) |field| {
                const spec = field.name;
                const opcode = field.value;
                if (opcode >= 256)
                    @compileError("Enum value exceeds 255: " ++ spec);
                defs[opcode] = spec;
            }
        },
        else => {
            @compileError("Expected an enum type");
        },
    }
}

fn enumField(comptime name: []const u8, comptime opcode: u8) std.builtin.Type.EnumField {
    var z_name: [name.len:0]u8 = @splat(' ');
    @memcpy(&z_name, name);
    return .{
        .name = &z_name,
        .value = opcode,
    };
}

pub fn mergeInstructionSets(comptime IA1: type, comptime IA2: type) type {
    comptime {
        var defs: [256]?[]const u8 = @splat(null);

        collectEnum(IA1, &defs);
        collectEnum(IA2, &defs);

        var used: usize = 0;
        for (defs) |def| {
            if (def != null) used += 1;
        }

        var fields: [used]std.builtin.Type.EnumField = undefined;
        var index: usize = 0;
        for (defs, 0..) |def, opcode| {
            if (def) |d| {
                fields[index] = enumField(d, @as(u8, opcode));
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

test "mergeInstructionSets" {
    const IA1 = enum(u8) {
        LDA = 0xA9,
        STA = 0x85,
        RTS = 0x60,
    };
    const IA2 = enum(u8) {
        LDX = 0xA2,
        STX = 0x86,
        RET = 0x60,
    };

    const MergedIA = mergeInstructionSets(IA1, IA2);
    try std.testing.expect(@intFromEnum(MergedIA.LDA) == 0xA9);
    try std.testing.expect(@intFromEnum(MergedIA.STA) == 0x85);
    try std.testing.expect(@intFromEnum(MergedIA.RET) == 0x60);
}

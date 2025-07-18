const std = @import("std");

const ISEnumDefs = [256]?[]const u8;

fn collectInstructionSet(comptime T: type, defs: *ISEnumDefs) void {
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

const EnumField = std.builtin.Type.EnumField;

fn makeEnumField(comptime name: []const u8, comptime opcode: u8) EnumField {
    var z_name: [name.len:0]u8 = @splat(' ');
    @memcpy(&z_name, name);
    return .{
        .name = &z_name,
        .value = opcode,
    };
}

fn makeInstructionSet(comptime defs: *const ISEnumDefs) type {
    comptime {
        var used: usize = 0;
        for (defs) |def| {
            if (def != null) used += 1;
        }

        var fields: [used]EnumField = undefined;
        var index: usize = 0;
        for (defs, 0..) |def, opcode| {
            if (def) |d| {
                fields[index] = makeEnumField(d, @as(u8, opcode));
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

pub fn mergeInstructionSets(comptime ISa: type, comptime ISb: type) type {
    comptime {
        var defs: ISEnumDefs = @splat(null);
        collectInstructionSet(ISa, &defs);
        collectInstructionSet(ISb, &defs);
        return makeInstructionSet(&defs);
    }
}

test "mergeInstructionSets" {
    const expect = std.testing.expect;
    const ISa = enum(u8) {
        LDA = 0xA9,
        STA = 0x85,
        RTS = 0x60,
    };
    const ISb = enum(u8) {
        LDX = 0xA2,
        STX = 0x86,
        RET = 0x60,
    };

    const MergedIA = mergeInstructionSets(ISa, ISb);
    try expect(@intFromEnum(MergedIA.LDA) == 0xA9);
    try expect(@intFromEnum(MergedIA.STA) == 0x85);
    try expect(@intFromEnum(MergedIA.RET) == 0x60);
}

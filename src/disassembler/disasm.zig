const std = @import("std");

const Writer = std.io.Writer;

const ResolverEnum = enum { zpg, abs, rel, @"#" };

pub fn Disassembler(comptime InstructionSet: type) type {
    comptime {
        _ = InstructionSet;

        return struct {
            const Self = @This();

            pub fn disassemble(
                self: Self,
                writer: *Writer,
                bytes: []const u8,
                offset: u16,
            ) !void {
                _ = self;
                _ = writer;
                _ = bytes;
                _ = offset;
            }
        };
    }
}

test Disassembler {
    const alloc = std.testing.allocator;

    const D = Disassembler(@import("../cpu/mos6502.zig").InstructionSet6502);
    const d = D{};

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    var w = Writer.Allocating.fromArrayList(alloc, &buf);
    defer w.deinit();

    try d.disassemble(&w.writer, &[_]u8{}, 0);
}

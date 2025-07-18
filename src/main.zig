const std = @import("std");
const machine = @import("cpu/cpu.zig");
const memory = @import("cpu/memory.zig");
const ct = @import("cpu/cpu_tools.zig");
const tube = @import("tube/os.zig");
const hb = @import("hibasic.zig");

const TRACE: u16 = 0xfe90;
const SNAPSHOT = ".snapshot.bbc";

const TubeHook = struct {
    const Self = @This();
    started: bool = false,
    pub fn @"hook:readline"(self: *Self, os: anytype) !?[]const u8 {
        _ = os;
        if (!self.started) {
            self.started = true;
            // std.debug.print("TubeOS started {*}\n", .{os});
            return "OLD";
        }
        return null;
    }
};

const TubeOS = tube.TubeOS(TubeHook);
const HiBasic = hb.HiBasic(TubeOS);

fn saveSnapshot(mc: HiBasic, file: []const u8) !void {
    const prog = mc.getProgram();
    const fh = try std.fs.cwd().createFile(file, .{ .truncate = true });
    defer fh.close();
    try fh.writeAll(prog);
    std.debug.print("Saved snapshot to {s}\n", .{file});
}

fn loadSnapshot(mc: *HiBasic, file: []const u8) !bool {
    var buf: [0x10000]u8 = undefined;
    const prog = std.fs.cwd().readFile(file, buf[0..]) catch |err| {
        if (err == error.FileNotFound) return false;
        return err;
    };
    @memcpy(mc.ram[0x800 .. 0x800 + prog.len], prog);
    std.debug.print("Loaded snapshot from {s}.\n", .{file});
    return true;
}

pub fn main() !void {
    var r_buf: [256]u8 = undefined;
    var w_buf: [0]u8 = undefined;
    var r = std.fs.File.stdin().reader(&r_buf);
    var w = std.fs.File.stdout().writer(&w_buf);

    var hook = TubeHook{};

    var os = try TubeOS.init(
        std.heap.page_allocator,
        &r.interface,
        &w.interface,
        &hook,
    );
    defer os.deinit();

    var ram: [0x10000]u8 = @splat(0);
    var mc = try HiBasic.init(&ram, &os);
    _ = try loadSnapshot(&mc, SNAPSHOT);

    var cpu = mc.cpu;
    cpu.poke8(TRACE, 0x00); // disable tracing
    while (!cpu.stopped) {
        cpu.step();
        switch (cpu.peek8(TRACE)) {
            0x00 => {},
            0x01 => std.debug.print("{f}\n", .{cpu}),
            else => {},
        }
    }

    std.debug.print("\nBye!\n", .{});
    try saveSnapshot(mc, SNAPSHOT);
}

test {
    @import("std").testing.refAllDecls(@This());
}

const std = @import("std");
const clap = @import("clap");
const machine = @import("cpu/cpu.zig");
const memory = @import("cpu/memory.zig");
const tube = @import("tube/os.zig");
const hb = @import("hibasic.zig");

const TRACE: u16 = 0xfe90;
const SNAPSHOT = ".snapshot";

const TubeOS = tube.TubeOS(hb.HiBasic);

const Tube65C02 = machine.CPU(
    @import("cpu/wdc65c02.zig").InstructionSet65C02,
    @import("cpu/address_modes.zig").AddressModes,
    @import("cpu/instructions.zig").Instructions,
    @import("cpu/alu.zig").ALU65C02,
    memory.FlatMemory,
    machine.NullInterruptSource,
    TubeOS,
    .{ .clear_decimal_on_int = true },
);

pub fn hiBasic(alloc: std.mem.Allocator, config: hb.HiBasicConfig) !void {
    var r_buf: [256]u8 = undefined;
    var w_buf: [0]u8 = undefined;
    var r = std.fs.File.stdin().reader(&r_buf);
    var w = std.fs.File.stdout().writer(&w_buf);

    var ram: [0x10000]u8 = @splat(0);
    var lang = try hb.HiBasic.init(
        alloc,
        config,
        &r.interface,
        &w.interface,
        &ram,
    );
    defer lang.deinit();

    var os = try TubeOS.init(
        alloc,
        &r.interface,
        &w.interface,
        &lang,
    );
    defer os.deinit();

    var cpu = Tube65C02.init(
        memory.FlatMemory{ .ram = &ram },
        machine.NullInterruptSource{},
        &os,
    );

    cpu.reset();
    os.reset(&cpu);
    lang.reset(&cpu);

    cpu.poke8(TRACE, 0x00); // disable tracing
    while (!cpu.stopped) {
        cpu.step();
        switch (cpu.peek8(TRACE)) {
            0x00 => {},
            0x01 => std.debug.print("{f}\n", .{cpu}),
            else => {},
        }
    }
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const parsers = comptime .{
        .prog = clap.parsers.string,
        .line = clap.parsers.string,
    };

    const params = comptime clap.parseParamsComptime(
        \\   -h, --help             Display this help and exit.
        \\   -c, --chain            CHAIN "prog"
        \\   -s, --sync             Auto load / save
        \\   -q, --quit             Quit after running
        \\   -e, --exec <line>...   Lines of BBC Basic to run
        \\   <prog>                 Program to load
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = alloc,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.helpToFile(.stdout(), clap.Help, &params, .{
            .description_on_new_line = false,
            .spacing_between_parameters = 0,
        });
        return;
    }

    var config = hb.HiBasicConfig{
        .chain = res.args.chain != 0,
        .quit = res.args.quit != 0,
        .sync = res.args.sync != 0,
        .exec = res.args.exec,
    };
    if (res.positionals.@"0") |prog| {
        config.prog_name = prog;
    }

    try hiBasic(alloc, config);
}

test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("disassembler/disasm.zig");
}

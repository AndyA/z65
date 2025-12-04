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

fn hiBasic(alloc: std.mem.Allocator, io: std.Io, config: hb.HiBasicConfig) !void {
    var r_buf: [256]u8 = undefined;
    var r = std.fs.File.stdin().reader(io, &r_buf);
    var w = std.fs.File.stdout().writer(&.{});

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

fn help(comptime params: anytype, full: bool) !void {
    var w_buf: [1024]u8 = undefined;
    var w = std.fs.File.stdout().writer(&w_buf);

    try w.interface.writeAll(
        \\hibasic: Acorn BBC HiBASIC
        \\
        \\Usage:
        \\    hibasic [OPTIONS] <prog>
        \\
        \\Options:
        \\
    );

    try clap.help(&w.interface, clap.Help, &params, .{ .max_width = 75 });
    if (full) {
        try w.interface.writeAll(
            \\
            \\ Notes:
            \\    Both native BBC Basic format source files and textual source files are 
            \\    supported by LOAD, SAVE and CHAIN. To work with textual source files
            \\    use the extension .bbc when editing them. Any other extension - or no
            \\    extension means BBC Basic native format.
            \\
            \\    There's currently no support for stopping a running program by hitting
            \\    Escape and Ctrl-C will kill hibasic completely. Fixes for both are
            \\    planned.
            \\
            \\    There's currently no VDU emulation - characters are sent as-is to
            \\    stdout. On one hand that means you can change the terminal colour
            \\    and print UTF-8 characters. On the other hand COLOUR etc don't work.
            \\    I plan to add support for mapping BBC colours to terminal colours.
            \\
            \\    Andy Armstrong <andy@hexten.net>
            \\
        );
    }

    try w.interface.writeAll("\n");
    try w.interface.flush();
}

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const alloc = gpa.allocator();
    const alloc = std.heap.page_allocator;
    const parsers = comptime .{
        .prog = clap.parsers.string,
        .line = clap.parsers.string,
    };
    var threaded: std.Io.Threaded = .init(alloc);
    defer threaded.deinit();

    const params = comptime clap.parseParamsComptime(
        \\    -h, --help            Display this help and exit.
        \\        --full-help       Print more help.
        \\    -c, --chain           Do CHAIN "prog" instead of LOAD "prog".
        \\    -s, --sync            Auto load when prog changes on disc.
        \\                          Auto save when prog changes in memory.
        \\    -q, --quit            Quit after running (*BYE).
        \\    -e, --exec <line>...  Lines of BBC Basic to run. May be
        \\                          used more than once to supply
        \\                          multiple lines.
        \\    <prog>                Program to load or run (--chain). May
        \\                          be text source or BBC Basic native.
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

    if (res.args.help != 0 or res.args.@"full-help" != 0) {
        try help(params, res.args.@"full-help" != 0);
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

    try hiBasic(alloc, threaded.io(), config);
}

test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("basic/model/vars.zig");
}

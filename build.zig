const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const hi_basic = b.addExecutable(.{
        .name = "hibasic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    hi_basic.root_module.addImport("clap", clap.module("clap"));

    const anyline = b.dependency("anyline", .{
        .target = target,
        .optimize = optimize,
    });

    hi_basic.root_module.addImport("anyline", anyline.module("anyline"));

    b.installArtifact(hi_basic);

    const mule = b.addExecutable(.{
        .name = "mule",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mule.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(mule);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(hi_basic);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mule_step = b.step("mule", "Run the mule");
    const mule_cmd = b.addRunArtifact(mule);
    mule_step.dependOn(&mule_cmd.step);
    mule_cmd.step.dependOn(b.getInstallStep());

    const exe_tests = b.addTest(.{
        .root_module = hi_basic.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

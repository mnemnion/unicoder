// Build script for unicoder
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const unicoder_module = b.addModule("unicoder", .{
        .root_source_file = b.path("src/unicoder.zig"),
        .target = target,
        .optimize = optimize,
    });

    const plan9_module = b.addModule("plan9", .{
        .root_source_file = b.path("plan9.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &[0][]const u8{};

    const module_unit_tests = b.addTest(.{
        .root_module = unicoder_module,
        .filters = test_filters,
    });

    const plan9_unit_tests = b.addTest(.{
        .root_module = plan9_module,
        .filters = test_filters,
    });

    const run_module_unit_tests = b.addRunArtifact(module_unit_tests);
    const run_plan9_unit_tests = b.addRunArtifact(plan9_unit_tests);

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_module_unit_tests.step);
    test_step.dependOn(&run_plan9_unit_tests.step);

    const run_kcov = b.addSystemCommand(&.{
        "kcov",
        "--clean",
        "--exclude-line=unreachable,expect(false)",
    });
    run_kcov.addPrefixedDirectoryArg("--include-pattern=", b.path("."));
    const coverage_output = run_kcov.addOutputDirectoryArg(".");
    run_kcov.addArtifactArg(module_unit_tests);

    run_kcov.enableTestRunnerMode();

    const install_coverage = b.addInstallDirectory(.{
        .source_dir = coverage_output,
        .install_dir = .{ .custom = "coverage" },
        .install_subdir = "",
    });

    const coverage_step = b.step("coverage", "Generate coverage (kcov must be installed)");
    coverage_step.dependOn(&install_coverage.step);
}

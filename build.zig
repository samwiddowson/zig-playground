const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "embed-tryout",
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
    });

    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "Run the embed tryout application");
    run_step.dependOn(&run_exe.step);
}

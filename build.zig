const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zigwin32 = b.dependency("zigwin32", .{});
    exe_mod.addImport("zigwin32", zigwin32.module("zigwin32"));
    const exe = b.addExecutable(.{
        .name = "windowsVulkan",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const vulkan_sdk = "C:/Zeugs/VulkanSDK/1.4.304.1/";
    exe.addIncludePath(.{ .cwd_relative = vulkan_sdk ++ "Include" });
    exe.addIncludePath(.{ .cwd_relative = vulkan_sdk ++ "Include/vulkan" });
    exe.addLibraryPath(.{ .cwd_relative = vulkan_sdk ++ "lib" });
    exe.linkSystemLibrary("vulkan-1");
    exe.linkLibC();
    const vulkan = b.dependency("vulkan_zig", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");
    exe.root_module.addImport("vulkan", vulkan);

    const zigimg_dependency = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zigimg", zigimg_dependency.module("zigimg"));
}

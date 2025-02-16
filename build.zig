// SPDX-FileCopyrightText: 2025 Eric Joldasov
//
// SPDX-License-Identifier: 0BSD

const std = @import("std");

pub fn build(b: *std.Build) void {
    // No steps for you, nothing to do here...
    b.top_level_steps.clearRetainingCapacity();
}

/// 1. Adds search pathes for includes and libraries.
/// 2. Links C standard library and sets PIC (needed by Python).
/// 3. Links Python and other required libraries.
///
/// Calls `python-config` under hood.
pub fn link_everything(mod: *std.Build.Module, python_version: []const u8) error{PythonNotFound}!void {
    const target = mod.resolved_target.?.result;
    // On Windows there are python310.exe and python310.dll instead.
    const normalized_python_version = if (target.os.tag == .windows)
        std.mem.replaceOwned(u8, mod.owner.graph.arena, python_version, ".", "") catch @panic("OOM")
    else
        python_version;

    const dependencies = get_python_info(mod.owner, normalized_python_version, target);
    if (dependencies.search_paths.include.len + dependencies.search_paths.library.len + dependencies.link_libraries.len == 0)
        return error.PythonNotFound;

    // 1. Adds search pathes for includes and libraries.
    for (dependencies.search_paths.include) |include_path| {
        mod.addIncludePath(.{ .cwd_relative = include_path });
    }
    for (dependencies.search_paths.library) |library_path| {
        mod.addLibraryPath(.{ .cwd_relative = library_path });
    }

    // 2. Links C standard library and sets PIC (needed by Python).
    mod.pic = true;
    mod.link_libc = true;

    // 3. Links Python and other required libraries.
    for (dependencies.link_libraries) |library_name| {
        mod.linkSystemLibrary(library_name, .{});
    }
    mod.linkSystemLibrary(
        mod.owner.fmt("python{s}", .{normalized_python_version}),
        // Should be already called and parsed from `get_python_info`.
        .{ .use_pkg_config = .no },
    );
}

fn get_python_info(b: *std.Build, python_version: []const u8, target: std.Target) struct {
    search_paths: struct {
        /// For example: -I/usr/include/python3.11
        include: [][]const u8,
        /// For example: -L/usr/lib64
        library: [][]const u8,
    },
    /// For example: -ldl -lm
    link_libraries: [][]const u8,
} {
    const arena = b.graph.arena;
    var includes: std.ArrayListUnmanaged([]const u8) = .empty;
    var libraries_path: std.ArrayListUnmanaged([]const u8) = .empty;
    var libraries_name: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        includes.deinit(arena);
        libraries_path.deinit(arena);
        libraries_name.deinit(arena);
    }

    var out_code: u8 = undefined;
    use_python_config: {
        const python_config_exe = b.findProgram(&.{b.fmt("python{s}-config", .{python_version})}, &.{}) catch |err| switch (err) {
            error.FileNotFound => break :use_python_config,
        };

        includes: {
            const stdout = b.runAllowFail(
                &.{ python_config_exe, "--embed", "--includes" },
                &out_code,
                .Inherit,
            ) catch break :includes;

            const count = std.mem.count(u8, stdout, " \n") + 1;
            includes.ensureUnusedCapacity(arena, count) catch @panic("OOM");

            var args = std.mem.tokenizeAny(u8, stdout, " \n");
            while (args.next()) |arg| {
                const include_path = if (std.mem.eql(u8, arg, "-I"))
                    args.next().?
                else if (std.mem.startsWith(u8, arg, "-I"))
                    std.mem.trimLeft(u8, arg, "-I")
                else
                    continue;

                includes.appendAssumeCapacity(include_path);
            }
            break :includes;
        }

        libraries: {
            const stdout = b.runAllowFail(
                &.{ python_config_exe, "--embed", "--ldflags" },
                &out_code,
                .Inherit,
            ) catch break :libraries;

            const count = std.mem.count(u8, stdout, " \n") + 1;
            libraries_path.ensureUnusedCapacity(arena, count) catch @panic("OOM");
            libraries_name.ensureUnusedCapacity(arena, count) catch @panic("OOM");

            var args = std.mem.tokenizeAny(u8, stdout, " \n");
            while (args.next()) |arg| {
                const optional_library_path = if (std.mem.eql(u8, arg, "-L"))
                    args.next().?
                else if (std.mem.startsWith(u8, arg, "-L"))
                    std.mem.trimLeft(u8, arg, "-L")
                else
                    null;

                const optional_library_name = if (std.mem.eql(u8, arg, "-l"))
                    args.next().?
                else if (std.mem.startsWith(u8, arg, "-l"))
                    std.mem.trimLeft(u8, arg, "-l")
                else
                    null;

                if (optional_library_path) |library_path| {
                    libraries_path.appendAssumeCapacity(library_path);
                }

                if (optional_library_name) |library_name| {
                    libraries_name.appendAssumeCapacity(library_name);
                }
            }
            break :libraries;
        }
        break :use_python_config;
    }

    use_pkg_config: {
        if (includes.items.len + libraries_path.items.len + libraries_name.items.len > 0)
            break :use_pkg_config;
        const pkg_config_exe = b.graph.env_map.get("PKG_CONFIG") orelse "pkg-config";

        includes: {
            const stdout = b.runAllowFail(
                &.{ pkg_config_exe, "--cflags-only-I", b.fmt("python-{s}-embed", .{python_version}) },
                &out_code,
                .Inherit,
            ) catch break :includes;

            const count = std.mem.count(u8, stdout, " \n") + 1;
            includes.ensureUnusedCapacity(arena, count) catch @panic("OOM");

            var args = std.mem.tokenizeAny(u8, stdout, " \n");
            while (args.next()) |arg| {
                const include_path = if (std.mem.eql(u8, arg, "-I"))
                    args.next().?
                else if (std.mem.startsWith(u8, arg, "-I"))
                    std.mem.trimLeft(u8, arg, "-I")
                else
                    continue;

                includes.appendAssumeCapacity(include_path);
            }
            break :includes;
        }

        libraries: {
            const stdout = b.runAllowFail(
                &.{ pkg_config_exe, "--libs", b.fmt("python-{s}-embed", .{python_version}) },
                &out_code,
                .Inherit,
            ) catch break :libraries;

            const count = std.mem.count(u8, stdout, " \n") + 1;
            libraries_path.ensureUnusedCapacity(arena, count) catch @panic("OOM");
            libraries_name.ensureUnusedCapacity(arena, count) catch @panic("OOM");

            var args = std.mem.tokenizeAny(u8, stdout, " \n");
            while (args.next()) |arg| {
                const optional_library_path = if (std.mem.eql(u8, arg, "-L"))
                    args.next().?
                else if (std.mem.startsWith(u8, arg, "-L"))
                    std.mem.trimLeft(u8, arg, "-L")
                else
                    null;

                const optional_library_name = if (std.mem.eql(u8, arg, "-l"))
                    args.next().?
                else if (std.mem.startsWith(u8, arg, "-l"))
                    std.mem.trimLeft(u8, arg, "-l")
                else
                    null;

                if (optional_library_path) |library_path| {
                    libraries_path.appendAssumeCapacity(library_path);
                }

                if (optional_library_name) |library_name| {
                    libraries_name.appendAssumeCapacity(library_name);
                }
            }
            break :libraries;
        }
        break :use_pkg_config;
    }

    use_python: {
        if (includes.items.len + libraries_path.items.len + libraries_name.items.len > 0)
            break :use_python;
        const python_exe = b.findProgram(&.{ b.fmt("python{s}", .{python_version}), "python3" }, &.{}) catch |err| switch (err) {
            error.FileNotFound => break :use_python,
        };

        includes: {
            const stdout = b.runAllowFail(&.{
                python_exe, "-c",
                \\import sysconfig
                \\print(sysconfig.get_path("include"))
            }, &out_code, .Inherit) catch break :includes;
            const includedir = std.mem.trim(u8, stdout, &std.ascii.whitespace);

            // Assume it can never be "None", unlike blocks below.
            if (includedir.len == 0) break :includes;
            includes.ensureUnusedCapacity(arena, 1) catch @panic("OOM");
            includes.appendAssumeCapacity(includedir);
            break :includes;
        }

        libraries_path: {
            const stdout = b.runAllowFail(&.{
                python_exe, "-c",
                \\import sysconfig
                \\print(sysconfig.get_config_var("LIBDIR"))
            }, &out_code, .Inherit) catch break :libraries_path;
            const libdir = std.mem.trim(u8, stdout, &std.ascii.whitespace);

            if (std.mem.eql(u8, libdir, "None")) break :libraries_path;
            libraries_path.ensureUnusedCapacity(arena, 1) catch @panic("OOM");
            libraries_path.appendAssumeCapacity(libdir);
            break :libraries_path;
        }

        libraries_name: {
            const stdout = b.runAllowFail(&.{
                python_exe, "-c",
                \\import sysconfig
                \\print(sysconfig.get_config_var("BLDLIBRARY"))
            }, &out_code, .Inherit) catch break :libraries_name;
            const flags = std.mem.trim(u8, stdout, &std.ascii.whitespace);
            if (std.mem.eql(u8, flags, "None")) break :libraries_name;

            const count = std.mem.count(u8, flags, " \n") + 1;
            libraries_name.ensureUnusedCapacity(arena, count) catch @panic("OOM");

            var args = std.mem.tokenizeAny(u8, flags, " \n");
            while (args.next()) |arg| {
                const library_name = if (std.mem.eql(u8, arg, "-l"))
                    args.next().?
                else if (std.mem.startsWith(u8, arg, "-l"))
                    std.mem.trimLeft(u8, arg, "-l")
                else
                    continue;

                libraries_name.appendAssumeCapacity(library_name);
            }
            break :libraries_name;
        }

        // Finally, if nothing helped, try to infer pathes
        // from python location itself on Windows:
        if (target.os.tag == .windows and
            (includes.items.len == 0 or libraries_path.items.len == 0))
        windows: {
            const root_dir = std.fs.path.dirname(python_exe) orelse break :windows;
            const cwd = std.fs.cwd();
            if (includes.items.len == 0) includes: {
                const include_subdir = std.fs.path.join(arena, &.{ root_dir, "Include\\" }) catch @panic("OOM");
                if (cwd.access(include_subdir, .{})) {
                    includes.ensureUnusedCapacity(arena, 1) catch @panic("OOM");
                    includes.appendAssumeCapacity(include_subdir);
                } else |_| break :includes;
            }
            if (libraries_path.items.len == 0) lib_path: {
                const lib_subdir = std.fs.path.join(arena, &.{ root_dir, "libs\\" }) catch @panic("OOM");
                if (cwd.access(lib_subdir, .{})) {
                    libraries_path.ensureUnusedCapacity(arena, 1) catch @panic("OOM");
                    libraries_path.appendAssumeCapacity(lib_subdir);
                } else |_| break :lib_path;
            }
        }
        break :use_python;
    }

    return .{
        .search_paths = .{
            .include = includes.toOwnedSlice(arena) catch @panic("OOM"),
            .library = libraries_path.toOwnedSlice(arena) catch @panic("OOM"),
        },
        .link_libraries = libraries_name.toOwnedSlice(arena) catch @panic("OOM"),
    };
}

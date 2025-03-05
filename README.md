<!--
SPDX-FileCopyrightText: 2025 Eric Joldasov

SPDX-License-Identifier: CC0-1.0
-->

# zig-python

[![REUSE status](https://api.reuse.software/badge/github.com/BratishkaErik/zig-python)](https://api.reuse.software/info/github.com/BratishkaErik/zig-python)

zig-python is a lightweight Zig build plugin to help you with linking
Python library and making CPython extensions in Zig. It uses `python-config`,
`pkg-config` and/or `import sysconfig` (+ plain path search on Windows)
to automatically retrieve required include paths and library paths
needed to find `Python.h` and shared library.

By default it skips running other methods if previous resulted
in at least one directory/library found.

Tested with Zig version `0.14.0`.

> [!IMPORTANT]
> This plugin does not (yet?) handle library install and naming
> as expected by CPython (f.e. `module.so` instead of default
> `libmodule.so` on Linux and `module.pyd` instead of `module.dll`
> on Windows). It is expected that you as a author will handle it by
> yourself.

> [!NOTE]
> See https://github.com/BratishkaErik/python-zig-extension-example for
> full example of building Python extension in Zig.

## Usage

Add dependency to your project:
```console
$ zig fetch --save 'git+https://github.com/BratishkaErik/zig-python#main'
```

It exposes one public function, `link_everything(module, python_version)`,
which you can use to... link everything to your module. Add this to your
`build.zig`:
```zig
const main_mod = b.createModule(.{
    .root_source_file = b.path("src/root.zig"),
    .target = target,
    .optimize = optimize,
});
// If you don't care about minor version, pass just "3" here.
@import("zig_python").link_everything(main_mod, "3.11") catch {
    // Handle error if needed
};
```

Example how to import library in your code:
```zig
const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});
```

Well done!

## Licenses

[![REUSE status](https://api.reuse.software/badge/github.com/BratishkaErik/zig-python)](https://api.reuse.software/info/github.com/BratishkaErik/zig-python)

This project is [REUSE-compliant](https://github.com/fsfe/reuse-tool),
text of licenses can be found in [LICENSES directory](LICENSES/).
Short overview:
* Code is licensed under 0BSD.
* This README and CI files are licensed under CC0-1.0.

[Comparison of used licenses](https://interoperable-europe.ec.europa.eu/licence/compare/0BSD;CC0-1.0).

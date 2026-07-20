<!--
SPDX-FileCopyrightText: 2025 Eric Joldasov
SPDX-License-Identifier: CC0-1.0
-->
<!--
style: Google Developer Documentation Style Guide
reason: Technical build-plugin reference with tutorial-first ordering; requires dense, unambiguous API docs and copy-pasteable code blocks.
doc-type: reference
audience: Zig developers building CPython extensions
-->

# zig-python

[![REUSE status][reuse-badge]][reuse-api]

**zig-python** is a lightweight Zig build plugin that links the Python
library and wires up CPython extension builds in Zig. It discovers the
required include paths (`Python.h`), library paths, and link flags
automatically by probing `python‑config`, `pkg‑config`, Python's
`sysconfig` module, and (on Windows) the filesystem — in that order.

Tested against Zig `0.14.0`.

> [!IMPORTANT]
> The plugin handles *linking* but not *installing*. Out of the box, Zig
> names a shared-object artifact `libmodule.so` on Linux and
> `module.dll` on Windows, but CPython expects `module.so` and
> `module.pyd` respectively. Adjust the install-step artifact name in
> your `build.zig` to match the platform convention.

> [!NOTE]
> A complete working extension is available at
> [python‑zig‑extension‑example][example-repo].

---

## Tutorial: Add zig-python to your project

This walk-through adds the plugin, links it to a module, and imports
`Python.h` in Zig code.

### 1. Fetch the dependency

```console
$ zig fetch --save 'git+https://github.com/BratishkaErik/zig-python#main'
```

### 2. Wire `link_everything` into your `build.zig`

```zig
const main_mod = b.createModule(.{
    .root_source_file = b.path("src/root.zig"),
    .target = target,
    .optimize = optimize,
});

// If you don't care about the minor version, pass just "3".
@import("zig_python").link_everything(main_mod, "3.11") catch {
    // Handle error if needed
};
```

### 3. Import `Python.h` in your extension

```zig
const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});
```

### 4. Build

```console
$ zig build
```

That is all the plugin needs. The binary will link against `libpython`
but will use the default shared-object name — adjust the install-step
artifact name in your `build.zig` to match the platform convention
(`module.so` on Linux/macOS, `module.pyd` on Windows).

---

## Explanation: How Python discovery works

The plugin tries four strategies in order, stopping as soon as one
returns usable paths.

### Fallback chain

```text
python-config  ──►  pkg-config  ──►  import sysconfig  ──►  Windows path fallback
```

1. **`python3.11-config --embed --includes`** and
    **`python3.11-config --embed --ldflags`** — used when the
    `python{version}-config` executable exists.
2. **`pkg-config python-3.11-embed --cflags-only-I`** and
    **`pkg-config python-3.11-embed --libs`** — used when
    `python-config` is absent.
3. **`python3.11 -c "import sysconfig; print(…)"`** — queries
    `sysconfig.get_path("include")`, `sysconfig.get_config_var("LIBDIR")`,
    and `sysconfig.get_config_var("BLDLIBRARY")`. Used when the first
    two strategies fail.
4. **Windows path heuristic** — if on Windows and the first three
    strategies returned nothing, the plugin walks upward from the
    `python.exe` location to find `Include/` and `libs/`
    sub-directories.

Each strategy independently gathers include directories, library
directories, and system link libraries (`dl`, `m`, …). The plugin
combines everything it collected into a single call to the module
functions `addIncludePath`, `addLibraryPath`, and
`linkSystemLibrary`.

### What the plugin does for you

- Adds all discovered include paths (so `@cInclude("Python.h")`
  resolves).
- Adds all discovered library paths.
- Links `libpython{version}` and any required system libraries (`dl`,
  `m`).
- Sets `mod.pic = true` (position-independent code is mandatory for
  shared libraries).
- Sets `mod.link_libc = true` (Python's C API depends on libc).

---

## Reference: `link_everything`

```zig
pub fn link_everything(
    mod: *std.Build.Module,
    python_version: []const u8,
) error{PythonNotFound}!void
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `mod` | `*std.Build.Module` | The Zig module to configure. Must have a resolved target. |
| `python_version` | `[]const u8` | Python version string, e.g. `"3.11"`. Pass `"3"` to let the system choose the latest Python 3.x. |

### Returns

| Result | Meaning |
|--------|---------|
| `void` | Success — include/library paths and link flags were applied. |
| `error.PythonNotFound` | None of the four discovery strategies produced any usable paths. |

### What it modifies on `mod`

| Property | Value | Reason |
|----------|-------|--------|
| `addIncludePath` | One or more paths | Locate `Python.h` |
| `addLibraryPath` | One or more paths | Locate `libpython` |
| `linkSystemLibrary` | `python{version}`, `dl`, `m`, … | Link Python and its dependencies |
| `pic` | `true` | Position-independent code (required for shared libs) |
| `link_libc` | `true` | Python C API depends on libc |

---

## Licenses

[![REUSE status][reuse-badge]][reuse-api]

This project is [REUSE‑compliant][reuse-tool]. License texts are in the
[`LICENSES/`][licenses-dir] directory.

| Scope | License |
|-------|---------|
| Source code (`build.zig`, `build.zig.zon`) | [0BSD][license-0bsd] |
| Documentation (`README.md`, CI files) | [CC0‑1.0][license-cc0] |

[Comparison of used licenses][license-compare].

[reuse-badge]: https://api.reuse.software/badge/github.com/BratishkaErik/zig-python
[reuse-api]: https://api.reuse.software/info/github.com/BratishkaErik/zig-python
[example-repo]: https://github.com/BratishkaErik/python-zig-extension-example
[reuse-tool]: https://github.com/fsfe/reuse-tool
[licenses-dir]: LICENSES/
[license-0bsd]: LICENSES/0BSD.txt
[license-cc0]: LICENSES/CC0-1.0.txt
[license-compare]: https://interoperable-europe.ec.europa.eu/licence/compare/0BSD;CC0-1.0

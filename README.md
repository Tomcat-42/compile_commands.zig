# compile_commands.zig

Simple build module to generate a `compile_commands.json`
file from [clang compilation database fragments](https://reviews.llvm.org/D66555) dir.

Note: I will only maintain support for zig master.

## Usage

Fetch the package:

```sh
zig fetch --save=compile_commands git+https://github.com/Tomcat-42/compile_commands.zig
```

Add the `-gen-cdb-fragment-path <DIR>` flag to your target. Here <DIR> could be any dir,
for example the zig cache:

```zig
const flags: []const []const u8 = &.{
    "-std=c23",
    "-Wall",
    "-Wextra",
    "-Werror",
    "-Wpedantic",
    "-fno-strict-aliasing",
    "-gen-cdb-fragment-path",
    b.fmt("{s}/{s}", .{ b.cache_root.path.?, "cdb" }),
};

const mod = b.createModule(.{
    .target = target,
    .optimize = optimize,
    .link_libc = true,
    .pic = true,
});

mod.addIncludePath(b.path("include"));
mod.addCSourceFiles(.{
    .root = b.path("src"),
    .files = &.{"main.c"},
    .flags = flags,
});

const exe = b.addExecutable(.{
    .name = "exe",
    .root_module = mod,
});
```

Now, create the step. `cdb_dir` is the fragments dir (the same that you added to the flags).
`output_path` is an optional output directory for `compile_commands.json` (defaults to the install prefix):

```zig
const CompileCommands = @import("compile_commands");

const cc_step = b.step("cc", "Generate Compile Commands Database");
const gen_cc = CompileCommands.create(b, .{
    .cdb_dir = .{ .cwd_relative = b.fmt("{s}/{s}", .{ b.cache_root.path.?, "cdb" }) },
    // .output_path = ".", // defaults to install prefix (zig-out/)
});
gen_cc.step.dependOn(&exe.step);
cc_step.dependOn(&gen_cc.step);
```

Finally, generate the file:

```sh
zig build cc
```

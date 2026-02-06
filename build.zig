const std = @import("std");
const Io = std.Io;
const json = std.json;
const mem = std.mem;
const Build = std.Build;
const Step = Build.Step;

const CompileCommands = @This();

step: Step,
cdb_dir_path: Build.LazyPath,
output_path: ?[]const u8,
generated_file: Build.GeneratedFile,

pub const base_id: Step.Id = .custom;

pub const Entry = struct {
    directory: []const u8,
    file: []const u8,
    arguments: ?[]const []const u8 = null,
    command: ?[]const []const u8 = null,
    output: []const u8,
};

pub const Options = struct {
    cdb_dir: Build.LazyPath,
    output_path: ?[]const u8 = null,
};

pub fn create(b: *Build, options: Options) *CompileCommands {
    const cc = b.allocator.create(CompileCommands) catch @panic("OOM");
    cc.* = .{
        .step = Step.init(.{
            .id = base_id,
            .name = "compile_commands",
            .owner = b,
            .makeFn = make,
        }),
        .cdb_dir_path = options.cdb_dir.dupe(b),
        .output_path = options.output_path,
        .generated_file = .{ .step = &cc.step },
    };
    options.cdb_dir.addStepDependencies(&cc.step);
    return cc;
}

pub fn getOutputPath(cc: *const CompileCommands) Build.LazyPath {
    return .{ .generated = .{ .file = &cc.generated_file } };
}

fn fromDir(io: Io, allocator: mem.Allocator, dir: Io.Dir) ![]const Entry {
    var entries: std.ArrayListUnmanaged(Entry) = .empty;
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |f| {
        if (f.kind != .file) continue;

        const contents = try dir.readFileAlloc(io, f.path, allocator, .unlimited);
        const entry = try json.parseFromSlice(
            Entry,
            allocator,
            contents[0 .. contents.len - 2], // trailing comma
            .{ .ignore_unknown_fields = true },
        );
        defer entry.deinit();

        try entries.append(allocator, entry.value);
    }

    return try entries.toOwnedSlice(allocator);
}

fn make(step: *Step, _: Step.MakeOptions) !void {
    const cc: *CompileCommands = @fieldParentPtr("step", step);
    const b = step.owner;
    const io = b.graph.io;
    const allocator = b.allocator;

    const cdb_path = cc.cdb_dir_path.getPath2(b, step);

    var dir = Io.Dir.cwd().openDir(io, cdb_path, .{ .iterate = true }) catch |err| {
        return step.fail("unable to open compile commands directory '{s}': {t}", .{ cdb_path, err });
    };
    defer dir.close(io);

    const entries = fromDir(io, allocator, dir) catch |err| {
        return step.fail("unable to read compile commands from '{s}': {t}", .{ cdb_path, err });
    };

    const contents = json.Stringify.valueAlloc(allocator, entries, .{
        .emit_null_optional_fields = false,
    }) catch @panic("OOM");

    const result_path = if (cc.output_path) |p|
        b.pathJoin(&.{ p, "compile_commands.json" })
    else
        b.pathJoin(&.{ b.install_path, "compile_commands.json" });

    var atomic = Io.Dir.cwd().createFileAtomic(io, result_path, .{
        .make_path = true,
        .replace = true,
    }) catch |err| {
        return step.fail("unable to create '{s}': {t}", .{ result_path, err });
    };
    defer atomic.deinit(io);

    atomic.file.writeStreamingAll(io, contents) catch |err| {
        return step.fail("unable to write '{s}': {t}", .{ result_path, err });
    };

    atomic.replace(io) catch |err| {
        return step.fail("unable to finalize '{s}': {t}", .{ result_path, err });
    };

    cc.generated_file.path = result_path;
}

pub fn build(b: *Build) void {
    _ = b;
}

const std = @import("std");
const helper = @import("helper.zig");

pub const logs_folder_name = "logs";
pub const log_file_name = "latest.log";
pub const log_file_name_old = "latest.log.old";

const Level = enum { info, warn, fail };

const Entry = struct {
    level: Level,
    message: []u8,
    next: ?*Entry,
};

var mutex: std.Io.Mutex = .init;
var cond: std.Io.Condition = .init;
var queue_head: ?*Entry = null;
var queue_tail: ?*Entry = null;
var log_file: ?std.Io.File = null;
var log_thread: ?std.Thread = null;
var running: bool = false;
var io: std.Io = undefined;
var gpa: std.mem.Allocator = undefined;

fn popLocked() ?*Entry {
    const entry = queue_head orelse return null;
    queue_head = entry.next;
    if (queue_head == null) queue_tail = null;
    return entry;
}

fn writeEntry(writer: *std.Io.File.Writer, entry: *Entry) void {
    const prefix, const plain = switch (entry.level) {
        .info => .{ "\x1b[34m[I]\x1b[0m", "[I]" },
        .warn => .{ "\x1b[33m[W]\x1b[0m", "[W]" },
        .fail => .{ "\x1b[31m[F]\x1b[0m", "[F]" },
    };

    std.debug.print("{s} {s}\n", .{ prefix, entry.message });

    writer.interface.print("{s} {s}\n", .{ plain, entry.message }) catch {};
    writer.interface.flush() catch {};

    gpa.free(entry.message);
    gpa.destroy(entry);
}

fn threadFunc() void {
    const tio = io;

    var file_buf: [8192]u8 = undefined;
    var writer = log_file.?.writer(tio, &file_buf);

    mutex.lockUncancelable(tio);
    while (true) {
        while (queue_head == null and running) {
            cond.waitUncancelable(tio, &mutex);
        }

        const entry = popLocked() orelse break;

        mutex.unlock(tio);
        writeEntry(&writer, entry);
        mutex.lockUncancelable(tio);
    }
    mutex.unlock(tio);
}

fn enqueue(level: Level, comptime fmt: []const u8, args: anytype) void {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);

    const message = std.fmt.allocPrint(gpa, fmt, args) catch return;
    errdefer gpa.free(message);

    const entry = gpa.create(Entry) catch return;
    entry.* = .{ .level = level, .message = message, .next = null };

    if (queue_tail) |tail| {
        tail.next = entry;
    } else {
        queue_head = entry;
    }
    queue_tail = entry;

    cond.signal(io);
}

pub fn init(logger_io: std.Io, allocator: std.mem.Allocator) bool {
    io = logger_io;
    gpa = allocator;

    var exe_buf: [4096]u8 = undefined;
    const exe_dir = helper.getExecutableDirectory(io, &exe_buf) orelse return false;

    var folder_buf: [4096]u8 = undefined;
    const folder = helper.makePath(&folder_buf, exe_dir, logs_folder_name) orelse {
        helper.printlnf("[F] Log folder path is too long", .{});
        return false;
    };

    var file_buf: [4096]u8 = undefined;
    const file_path = helper.makePath(&file_buf, folder, log_file_name) orelse {
        helper.printlnf("[F] Log file path is too long", .{});
        return false;
    };

    var old_buf: [4096]u8 = undefined;
    const old_path = helper.makePath(&old_buf, folder, log_file_name_old) orelse {
        helper.printlnf("[F] Old log file path is too long", .{});
        return false;
    };

    const cwd = std.Io.Dir.cwd();

    if (cwd.statFile(io, folder, .{})) |st| {
        if (st.kind != .directory) {
            helper.printlnf("[F] \"logs\" exists but is not a directory", .{});
            return false;
        }
    } else |err| switch (err) {
        error.FileNotFound => {
            helper.printlnf("[I] \"logs\" folder does not exist, creating...", .{});
            cwd.createDirPath(io, folder) catch {
                helper.printlnf("[F] Failed to create logs folder", .{});
                return false;
            };
        },
        else => return false,
    }

    if (cwd.statFile(io, file_path, .{})) |_| {
        cwd.rename(file_path, cwd, old_path, io) catch {
            helper.printlnf("[W] Failed to rename log file", .{});
        };
    } else |_| {}

    log_file = cwd.createFile(io, file_path, .{}) catch {
        helper.printlnf("[F] Failed to create log file", .{});
        return false;
    };

    running = true;
    log_thread = std.Thread.spawn(.{}, threadFunc, .{}) catch {
        helper.printlnf("[F] Failed to create log thread", .{});
        log_file.?.close(io);
        log_file = null;
        running = false;
        return false;
    };

    return true;
}

pub fn deinit() void {
    mutex.lockUncancelable(io);
    running = false;
    cond.signal(io);
    mutex.unlock(io);

    if (log_thread) |t| t.join();
    log_thread = null;

    if (log_file) |*f| f.close(io);
    log_file = null;
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    enqueue(.info, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    enqueue(.warn, fmt, args);
}

pub fn fail(comptime fmt: []const u8, args: anytype) void {
    enqueue(.fail, fmt, args);
}

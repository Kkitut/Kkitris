const std = @import("std");
const field_mod = @import("field.zig");

pub const RulesConfig = struct {
    w: u32 = 10,
    h: u32 = 40,
    visible_h: u32 = 20,

    seed: u64 = 0x1234_5678_9abc_def0,
    preview_count: u8 = 5,
    hold_enabled: bool = true,

    endless: bool = true,

    das_sec: f32 = 0.167,
    arr_sec: f32 = 0.033,
    dcd_sec: f32 = 0.017,
    sdf: f32 = 6.0,
    lock_delay_sec: f32 = 0.5,
    max_lock_resets: u32 = 15,
    are_sec: f32 = 0.2,

    start_level: u32 = 1,
    lines_per_level: u32 = 10,

    pub fn validate(self: RulesConfig) !void {
        if (self.w < field_mod.MIN_W or self.w > field_mod.MAX_W) return error.BadWidth;
        if (self.h < field_mod.MIN_H or self.h > field_mod.MAX_H) return error.BadHeight;
        if (self.visible_h == 0 or self.visible_h > self.h) return error.BadVisibleHeight;
        if (self.preview_count > 7) return error.BadPreview;
        if (self.das_sec < 0 or self.arr_sec < 0 or self.dcd_sec < 0) return error.BadHandling;
        if (self.sdf <= 0) return error.BadHandling;
    }

    pub fn gravityInterval(level: u32) f32 {
        const lv: f32 = @floatFromInt(@max(level, 1));
        const base = @max(0.8 - (lv - 1.0) * 0.007, 0.01);
        return @max(std.math.pow(f32, base, lv - 1.0), 1.0 / 60.0 / 20.0);
    }
};

pub const SETTINGS_PATH = "settings.json";

const MAX_SETTINGS_BYTES = 64 * 1024;

pub fn toJson(alloc: std.mem.Allocator, cfg: RulesConfig) ![]u8 {
    return std.json.Stringify.valueAlloc(alloc, cfg, .{ .whitespace = .indent_2 });
}

pub fn fromJson(alloc: std.mem.Allocator, text: []const u8) !RulesConfig {
    const parsed = std.json.parseFromSlice(
        RulesConfig,
        alloc,
        text,
        .{ .ignore_unknown_fields = true },
    ) catch return error.BadJson;
    defer parsed.deinit();
    const cfg = parsed.value;
    try cfg.validate();
    return cfg;
}

pub fn save(io: std.Io, alloc: std.mem.Allocator, path: []const u8, cfg: RulesConfig) !void {
    const text = try toJson(alloc, cfg);
    defer alloc.free(text);
    const cwd = std.Io.Dir.cwd();
    var file = cwd.createFile(io, path, .{}) catch return error.SaveFailed;
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var writer = file.writer(io, &buf);
    writer.interface.writeAll(text) catch return error.SaveFailed;
    writer.interface.flush() catch return error.SaveFailed;
}

pub fn load(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !?RulesConfig {
    const cwd = std.Io.Dir.cwd();
    var probe = cwd.openFile(io, path, .{}) catch return null;
    probe.close(io);
    const text = cwd.readFileAlloc(io, path, alloc, .limited(MAX_SETTINGS_BYTES)) catch
        return error.LoadFailed;
    defer alloc.free(text);
    return fromJson(alloc, text) catch return error.BadJson;
}

test "config" {
    try (RulesConfig{}).validate();
    try (RulesConfig{ .w = 4, .h = 1, .visible_h = 1 }).validate();
    try (RulesConfig{ .w = 100, .h = 100, .visible_h = 100 }).validate();
    try std.testing.expectError(error.BadWidth, (RulesConfig{ .w = 0 }).validate());
}

test "gravity" {
    try std.testing.expect(RulesConfig.gravityInterval(1) > RulesConfig.gravityInterval(9));
}

test "json roundtrip" {
    const alloc = std.testing.allocator;
    const cfg = RulesConfig{
        .w = 10,
        .h = 40,
        .seed = 0xdead_beef_1234_5678,
        .das_sec = 0.167,
        .arr_sec = 0.033,
        .dcd_sec = 0.017,
        .sdf = 6.0,
        .endless = false,
    };
    const text = try toJson(alloc, cfg);
    defer alloc.free(text);
    const back = try fromJson(alloc, text);
    try std.testing.expect(std.meta.eql(cfg, back));
}

test "json partial defaults" {
    const alloc = std.testing.allocator;
    const back = try fromJson(alloc, "{}");
    try std.testing.expect(std.meta.eql(RulesConfig{}, back));
    const half = try fromJson(alloc, "{\"das_sec\":0.5,\"unknown_future_field\":123}");
    try std.testing.expectEqual(@as(f32, 0.5), half.das_sec);
    const def = RulesConfig{};
    try std.testing.expectEqual(def.arr_sec, half.arr_sec);
}

test "json invalid" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.BadJson, fromJson(alloc, "{bad"));
    try std.testing.expectError(error.BadHandling, fromJson(alloc, "{\"sdf\":0}"));
    try std.testing.expectError(error.BadHandling, fromJson(alloc, "{\"das_sec\":-1}"));
}

test "save load file" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    const path = "/tmp/kkitris_test_settings.json";
    const cfg = RulesConfig{ .das_sec = 0.2, .sdf = 12.0, .seed = 99 };
    try save(io, alloc, path, cfg);
    const back = (try load(io, alloc, path)).?;
    try std.testing.expect(std.meta.eql(cfg, back));
    const cwd = std.Io.Dir.cwd();
    cwd.deleteFile(io, path) catch {};
}

test "load missing is null" {
    const alloc = std.testing.allocator;
    const back = try load(std.testing.io, alloc, "/tmp/kkitris_no_such_file_xyz.json");
    try std.testing.expect(back == null);
}

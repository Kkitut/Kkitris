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

    das_sec: f32 = 0.12,
    arr_sec: f32 = 0.02,
    soft_factor: f32 = 20.0,
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
    }

    pub fn gravityInterval(level: u32) f32 {
        const lv: f32 = @floatFromInt(@max(level, 1));
        const base = @max(0.8 - (lv - 1.0) * 0.007, 0.01);
        return @max(std.math.pow(f32, base, lv - 1.0), 1.0 / 60.0 / 20.0);
    }
};

test "config" {
    try (RulesConfig{}).validate();
    try (RulesConfig{ .w = 4, .h = 1, .visible_h = 1 }).validate();
    try (RulesConfig{ .w = 100, .h = 100, .visible_h = 100 }).validate();
    try std.testing.expectError(error.BadWidth, (RulesConfig{ .w = 0 }).validate());
}

test "gravity" {
    try std.testing.expect(RulesConfig.gravityInterval(1) > RulesConfig.gravityInterval(9));
}

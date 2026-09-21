const std = @import("std");

pub const InstanceData = extern struct {
    color: [4]f32,
    position: [2]f32,
    scale: [2]f32,
    rotation: f32,
    texture_index: u32,
};

pub const MAX_INSTANCES: usize = 4096;

pub const Skin = struct {
    pub const white: u32 = 0;
    pub const i: u32 = 1;
    pub const o: u32 = 2;
    pub const t: u32 = 3;
    pub const s: u32 = 4;
    pub const z: u32 = 5;
    pub const j: u32 = 6;
    pub const l: u32 = 7;
    pub const garbage: u32 = 8;
    pub const count: u32 = 9;
    pub const size_px: u32 = 24;

    pub fn forMino(mino: @import("../core/cell.zig").MinoKind) u32 {
        return switch (mino) {
            .none => white,
            .i => i,
            .o => o,
            .t => t,
            .s => s,
            .z => z,
            .j => j,
            .l => l,
            .garbage => garbage,
        };
    }
};

pub fn push(list: []InstanceData, count: *usize, inst: InstanceData) bool {
    if (count.* >= list.len) return false;
    list[count.*] = inst;
    count.* += 1;
    return true;
}

test "inst layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(InstanceData, "color"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(InstanceData, "position"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(InstanceData, "scale"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(InstanceData, "rotation"));
    try std.testing.expectEqual(@as(usize, 36), @offsetOf(InstanceData, "texture_index"));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(InstanceData));
}

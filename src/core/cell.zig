const std = @import("std");

pub const MinoKind = enum(u8) {
    none = 0,
    i = 1,
    o = 2,
    t = 3,
    s = 4,
    z = 5,
    j = 6,
    l = 7,
    garbage = 8,

    pub fn rgb(self: MinoKind) [3]f32 {
        return switch (self) {
            .none => .{ 0, 0, 0 },
            .i => .{ 0.0, 0.9, 0.9 },
            .o => .{ 1.0, 0.85, 0.1 },
            .t => .{ 0.7, 0.3, 1.0 },
            .s => .{ 0.2, 0.9, 0.3 },
            .z => .{ 1.0, 0.25, 0.3 },
            .j => .{ 0.25, 0.4, 1.0 },
            .l => .{ 1.0, 0.55, 0.15 },
            .garbage => .{ 0.55, 0.57, 0.6 },
        };
    }
};

pub const BlockKind = enum(u8) {
    empty = 0,
    normal = 1,
    garbage = 2,
    solid = 3,
};

pub const LinkMask = packed struct(u4) {
    px: bool = false,
    nx: bool = false,
    py: bool = false,
    ny: bool = false,
};

pub const Cell = struct {
    occupied: bool = false,
    kind: BlockKind = .empty,
    mino: MinoKind = .none,
    link: LinkMask = .{},

    pub const EMPTY: Cell = .{};

    pub fn make(kind: BlockKind, mino: MinoKind) Cell {
        return .{ .occupied = true, .kind = kind, .mino = mino };
    }

    pub fn isSolid(self: Cell) bool {
        return self.occupied and self.kind == .solid;
    }

    pub fn clearsWithLine(self: Cell) bool {
        return self.occupied and self.kind != .solid;
    }
};

test "cell size" {
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(Cell));
    const c = Cell.make(.normal, .t);
    try std.testing.expect(c.occupied);
    try std.testing.expect(c.clearsWithLine());
    try std.testing.expect(!Cell.EMPTY.occupied);
    try std.testing.expect(!Cell.make(.solid, .garbage).clearsWithLine());
}

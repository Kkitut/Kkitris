const std = @import("std");
const cell_mod = @import("cell.zig");
const MinoKind = cell_mod.MinoKind;

pub const PieceKind = enum(u8) {
    i = 0,
    o = 1,
    t = 2,
    s = 3,
    z = 4,
    j = 5,
    l = 6,

    pub const COUNT = 7;

    pub fn mino(self: PieceKind) MinoKind {
        return switch (self) {
            .i => .i,
            .o => .o,
            .t => .t,
            .s => .s,
            .z => .z,
            .j => .j,
            .l => .l,
        };
    }

    pub fn fromBagIndex(i: u8) PieceKind {
        return @enumFromInt(i % COUNT);
    }
};

pub const Rotation = enum(u2) {
    spawn = 0,
    right = 1,
    half = 2,
    left = 3,

    pub fn cw(self: Rotation) Rotation {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 1) & 3);
    }
    pub fn ccw(self: Rotation) Rotation {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 3) & 3);
    }
    pub fn half_turn(self: Rotation) Rotation {
        return @enumFromInt((@as(u3, @intFromEnum(self)) + 2) & 3);
    }
};

pub const MASKS: [7][4][4]u16 = .{
    // I
    .{
        .{ 0b0000, 0b1111, 0b0000, 0b0000 },
        .{ 0b0010, 0b0010, 0b0010, 0b0010 },
        .{ 0b0000, 0b0000, 0b1111, 0b0000 },
        .{ 0b0100, 0b0100, 0b0100, 0b0100 },
    },
    // O
    .{
        .{ 0b0110, 0b0110, 0b0000, 0b0000 },
        .{ 0b0110, 0b0110, 0b0000, 0b0000 },
        .{ 0b0110, 0b0110, 0b0000, 0b0000 },
        .{ 0b0110, 0b0110, 0b0000, 0b0000 },
    },
    // T
    .{
        .{ 0b0000, 0b0000, 0b0111, 0b0010 },
        .{ 0b0000, 0b0010, 0b0110, 0b0010 },
        .{ 0b0000, 0b0010, 0b0111, 0b0000 },
        .{ 0b0000, 0b0010, 0b0011, 0b0010 },
    },
    // S
    .{
        .{ 0b0110, 0b1100, 0b0000, 0b0000 },
        .{ 0b0100, 0b0110, 0b0010, 0b0000 },
        .{ 0b0000, 0b0110, 0b1100, 0b0000 },
        .{ 0b1000, 0b1100, 0b0100, 0b0000 },
    },
    // Z
    .{
        .{ 0b1100, 0b0110, 0b0000, 0b0000 },
        .{ 0b0010, 0b0110, 0b0100, 0b0000 },
        .{ 0b0000, 0b1100, 0b0110, 0b0000 },
        .{ 0b0100, 0b1100, 0b1000, 0b0000 },
    },
    // J
    .{
        .{ 0b0000, 0b1110, 0b0010, 0b0000 },
        .{ 0b0100, 0b0100, 0b1100, 0b0000 },
        .{ 0b1000, 0b1110, 0b0000, 0b0000 },
        .{ 0b0110, 0b0100, 0b0100, 0b0000 },
    },
    // L
    .{
        .{ 0b0000, 0b1110, 0b1000, 0b0000 },
        .{ 0b1100, 0b0100, 0b0100, 0b0000 },
        .{ 0b0010, 0b1110, 0b0000, 0b0000 },
        .{ 0b0100, 0b0100, 0b0110, 0b0000 },
    },
};

pub fn mask(kind: PieceKind, rot: Rotation) [4]u16 {
    return MASKS[@intFromEnum(kind)][@intFromEnum(rot)];
}

pub fn bounds(m: [4]u16) struct { w: u8, h: u8 } {
    var w: u8 = 0;
    var h: u8 = 0;
    for (m, 0..) |row, y| {
        if (row != 0) h = @intCast(y + 1);
        if (row & 0b0001 != 0) w = @max(w, 1);
        if (row & 0b0010 != 0) w = @max(w, 2);
        if (row & 0b0100 != 0) w = @max(w, 3);
        if (row & 0b1000 != 0) w = @max(w, 4);
    }
    return .{ .w = w, .h = h };
}

test "4 cells" {
    for (0..7) |k| {
        for (0..4) |r| {
            var n: u32 = 0;
            for (MASKS[k][r]) |row| n += @popCount(row);
            try std.testing.expectEqual(@as(u32, 4), n);
        }
    }
}

test "I mask" {
    try std.testing.expectEqual(@as(u16, 0b1111), MASKS[0][0][1]);
}

fn cellsOf(m: [4]u16, out: *[4][2]i32) void {
    var n: usize = 0;
    for (m, 0..) |row, y| {
        var bits = row;
        var x: i32 = 0;
        while (bits != 0) : (x += 1) {
            if (bits & 1 != 0) {
                out[n] = .{ x, @intCast(y) };
                n += 1;
            }
            bits >>= 1;
        }
    }
    std.debug.assert(n == 4);
}

fn normalizedCells(m: [4]u16) [4][2]i32 {
    var cells: [4][2]i32 = undefined;
    cellsOf(m, &cells);
    var min_x = cells[0][0];
    var min_y = cells[0][1];
    for (cells[1..]) |c| {
        min_x = @min(min_x, c[0]);
        min_y = @min(min_y, c[1]);
    }
    for (&cells) |*c| {
        c[0] -= min_x;
        c[1] -= min_y;
    }
    for (1..4) |i| {
        var j = i;
        while (j > 0 and (cells[j][0] < cells[j - 1][0] or
            (cells[j][0] == cells[j - 1][0] and cells[j][1] < cells[j - 1][1])))
        {
            const t = cells[j];
            cells[j] = cells[j - 1];
            cells[j - 1] = t;
            j -= 1;
        }
    }
    return cells;
}

fn cwStep(cells: [4][2]i32) [4][2]i32 {
    var out = cells;
    var min_x: i32 = std.math.maxInt(i32);
    var min_y: i32 = std.math.maxInt(i32);
    for (&out) |*c| {
        const nx = c[1];
        const ny = -c[0];
        c[0] = nx;
        c[1] = ny;
        min_x = @min(min_x, nx);
        min_y = @min(min_y, ny);
    }
    for (&out) |*c| {
        c[0] -= min_x;
        c[1] -= min_y;
    }
    for (1..4) |i| {
        var j = i;
        while (j > 0 and (out[j][0] < out[j - 1][0] or
            (out[j][0] == out[j - 1][0] and out[j][1] < out[j - 1][1])))
        {
            const t = out[j];
            out[j] = out[j - 1];
            out[j - 1] = t;
            j -= 1;
        }
    }
    return out;
}

test "spawn shapes" {
    try std.testing.expectEqual(MASKS[@intFromEnum(PieceKind.j)][0], [4]u16{ 0, 0b1110, 0b0010, 0 });
    try std.testing.expectEqual(MASKS[@intFromEnum(PieceKind.l)][0], [4]u16{ 0, 0b1110, 0b1000, 0 });
    try std.testing.expectEqual(MASKS[@intFromEnum(PieceKind.t)][0], [4]u16{ 0, 0, 0b0111, 0b0010 });
    try std.testing.expectEqual(MASKS[@intFromEnum(PieceKind.s)][0], [4]u16{ 0b0110, 0b1100, 0, 0 });
    try std.testing.expectEqual(MASKS[@intFromEnum(PieceKind.z)][0], [4]u16{ 0b1100, 0b0110, 0, 0 });
}

test "rot cycle" {
    for (0..7) |k| {
        const kind: PieceKind = @enumFromInt(k);
        var cur = normalizedCells(mask(kind, .spawn));
        const seq = [_]Rotation{ .right, .half, .left, .spawn };
        for (seq) |rot| {
            cur = cwStep(cur);
            try std.testing.expectEqual(normalizedCells(mask(kind, rot)), cur);
        }
    }
}

test "rot wrap" {
    const all = [_]Rotation{ .spawn, .right, .half, .left };
    for (all) |r| {
        try std.testing.expectEqual(r, r.cw().cw().cw().cw());
        try std.testing.expectEqual(r, r.ccw().ccw().ccw().ccw());
        try std.testing.expectEqual(r, r.half_turn().half_turn());
        try std.testing.expectEqual(r.cw().cw(), r.half_turn());
        try std.testing.expectEqual(r.cw(), r.ccw().ccw().ccw());
    }
    try std.testing.expectEqual(Rotation.right, Rotation.spawn.cw());
    try std.testing.expectEqual(Rotation.left, Rotation.spawn.ccw());
    try std.testing.expectEqual(Rotation.right, Rotation.left.half_turn());
}

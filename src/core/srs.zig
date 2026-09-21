const std = @import("std");
const piece_mod = @import("piece.zig");
const PieceKind = piece_mod.PieceKind;
const Rotation = piece_mod.Rotation;
const field_mod = @import("field.zig");
const Field = field_mod.Field;

pub const Kick = struct { dx: i8, dy: i8 };

fn jlstzTable(from: Rotation, to: Rotation) [5]Kick {
    const f = @intFromEnum(from);
    const t = @intFromEnum(to);
    if (f == 0 and t == 1) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = -1, .dy = 1 }, .{ .dx = 0, .dy = -2 }, .{ .dx = -1, .dy = -2 } };
    if (f == 1 and t == 0) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = 1, .dy = -1 }, .{ .dx = 0, .dy = 2 }, .{ .dx = 1, .dy = 2 } };
    if (f == 1 and t == 2) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = 1, .dy = -1 }, .{ .dx = 0, .dy = 2 }, .{ .dx = 1, .dy = 2 } };
    if (f == 2 and t == 1) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = -1, .dy = 1 }, .{ .dx = 0, .dy = -2 }, .{ .dx = -1, .dy = -2 } };
    if (f == 2 and t == 3) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = 1, .dy = 1 }, .{ .dx = 0, .dy = -2 }, .{ .dx = 1, .dy = -2 } };
    if (f == 3 and t == 2) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = -1, .dy = -1 }, .{ .dx = 0, .dy = 2 }, .{ .dx = -1, .dy = 2 } };
    if (f == 3 and t == 0) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = -1, .dy = -1 }, .{ .dx = 0, .dy = 2 }, .{ .dx = -1, .dy = 2 } };
    if (f == 0 and t == 3) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = 1, .dy = 1 }, .{ .dx = 0, .dy = -2 }, .{ .dx = 1, .dy = -2 } };
    return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 1 }, .{ .dx = 1, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = 0, .dy = -1 } };
}

fn iTable(from: Rotation, to: Rotation) [5]Kick {
    const f = @intFromEnum(from);
    const t = @intFromEnum(to);
    if (f == 0 and t == 1) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -2, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = -2, .dy = -1 }, .{ .dx = 1, .dy = 2 } };
    if (f == 1 and t == 0) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 2, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = 2, .dy = 1 }, .{ .dx = -1, .dy = -2 } };
    if (f == 1 and t == 2) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = 2, .dy = 0 }, .{ .dx = -1, .dy = 2 }, .{ .dx = 2, .dy = -1 } };
    if (f == 2 and t == 1) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = -2, .dy = 0 }, .{ .dx = 1, .dy = -2 }, .{ .dx = -2, .dy = 1 } };
    if (f == 2 and t == 3) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 2, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = 2, .dy = 1 }, .{ .dx = -1, .dy = -2 } };
    if (f == 3 and t == 2) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -2, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = -2, .dy = -1 }, .{ .dx = 1, .dy = 2 } };
    if (f == 3 and t == 0) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = -2, .dy = 0 }, .{ .dx = 1, .dy = -2 }, .{ .dx = -2, .dy = 1 } };
    if (f == 0 and t == 3) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = 2, .dy = 0 }, .{ .dx = -1, .dy = 2 }, .{ .dx = 2, .dy = -1 } };
    return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 1 }, .{ .dx = 0, .dy = -1 }, .{ .dx = 1, .dy = 0 }, .{ .dx = -1, .dy = 0 } };
}

pub fn kickList(kind: PieceKind, from: Rotation, to: Rotation) [6]Kick {
    // SRS+ 180 kicks (TETR.IO style): one table per opposite pair,
    // mirrored per direction. Same +y-up convention as the 90° tables.
    const f: u3 = @intFromEnum(from);
    const t: u3 = @intFromEnum(to);
    if ((f + 2) & 3 == t) {
        if (kind == .o) return [6]Kick{ .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 } };
        if (kind == .i) {
            if (f == 0) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -2, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = 0, .dy = 1 }, .{ .dx = -2, .dy = 1 }, .{ .dx = 1, .dy = 1 } };
            if (f == 2) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 2, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = 0, .dy = -1 }, .{ .dx = 2, .dy = -1 }, .{ .dx = -1, .dy = -1 } };
            if (f == 1) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = 2, .dy = 0 }, .{ .dx = 0, .dy = -1 }, .{ .dx = -1, .dy = -1 }, .{ .dx = 2, .dy = -1 } };
            return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = -2, .dy = 0 }, .{ .dx = 0, .dy = 1 }, .{ .dx = 1, .dy = 1 }, .{ .dx = -2, .dy = 1 } };
        }
        if (f == 0) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 1 }, .{ .dx = 1, .dy = 1 }, .{ .dx = -1, .dy = 1 }, .{ .dx = 1, .dy = 0 }, .{ .dx = -1, .dy = 0 } };
        if (f == 2) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = -1 }, .{ .dx = 1, .dy = -1 }, .{ .dx = -1, .dy = -1 }, .{ .dx = 1, .dy = 0 }, .{ .dx = -1, .dy = 0 } };
        if (f == 1) return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 1, .dy = 0 }, .{ .dx = 1, .dy = 1 }, .{ .dx = 1, .dy = -1 }, .{ .dx = 0, .dy = 1 }, .{ .dx = 0, .dy = -1 } };
        return .{ .{ .dx = 0, .dy = 0 }, .{ .dx = -1, .dy = 0 }, .{ .dx = -1, .dy = 1 }, .{ .dx = -1, .dy = -1 }, .{ .dx = 0, .dy = 1 }, .{ .dx = 0, .dy = -1 } };
    }
    const five = switch (kind) {
        .o => [5]Kick{ .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 } },
        .i => iTable(from, to),
        else => jlstzTable(from, to),
    };
    // Pad to 6 with a (0,0) re-test: deterministic, so it can never flip
    // a failure into success; keeps one uniform table size for SRS+ 180s.
    return .{ five[0], five[1], five[2], five[3], five[4], .{ .dx = 0, .dy = 0 } };
}

pub const RotateResult = struct {
    ok: bool,
    x: i32,
    y: i32,
    rot: Rotation,
    kick_index: u8,
};

pub fn tryRotate(
    field: *const Field,
    kind: PieceKind,
    from: Rotation,
    to: Rotation,
    px: i32,
    py: i32,
) RotateResult {
    const masks = piece_mod.mask(kind, to);
    const kicks = kickList(kind, from, to);
    for (kicks, 0..) |k, i| {
        const nx = px + @as(i32, k.dx);
        const ny = py + @as(i32, k.dy);
        if (!field.collides(masks, nx, ny)) {
            return .{ .ok = true, .x = nx, .y = ny, .rot = to, .kick_index = @intCast(i) };
        }
        if (kind == .o) break;
    }
    return .{ .ok = false, .x = px, .y = py, .rot = from, .kick_index = 0 };
}

test "T rotate" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    const r = tryRotate(&f, .t, .spawn, .right, 3, 10);
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(i32, 3), r.x);
}

test "wallkick" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    const r = tryRotate(&f, .t, .spawn, .right, -1, 5);
    _ = r;
}

test "O rot" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    const r = tryRotate(&f, .o, .spawn, .right, 4, 0);
    try std.testing.expect(r.ok);
}

test "S floor kick" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    const r = tryRotate(&f, .s, .spawn, .right, 4, -2);
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u8, 2), r.kick_index);
    try std.testing.expectEqual(@as(i32, 3), r.x);
    try std.testing.expectEqual(@as(i32, -1), r.y);
}

test "Z floor kick" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    const r = tryRotate(&f, .z, .spawn, .left, 4, -2);
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u8, 2), r.kick_index);
    try std.testing.expectEqual(@as(i32, 5), r.x);
    try std.testing.expectEqual(@as(i32, -1), r.y);
}

test "180 basic" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    const kinds = [_]PieceKind{ .i, .o, .t, .s, .z, .j, .l };
    const pairs = [_][2]Rotation{
        .{ .spawn, .half }, .{ .half, .spawn },
        .{ .right, .left }, .{ .left, .right },
    };
    for (kinds) |k| {
        for (pairs) |p| {
            const r = tryRotate(&f, k, p[0], p[1], 4, 10);
            try std.testing.expect(r.ok);
            try std.testing.expectEqual(@as(u8, 0), r.kick_index);
            try std.testing.expectEqual(@as(i32, 4), r.x);
            try std.testing.expectEqual(@as(i32, 10), r.y);
        }
    }
}

test "180 kick T" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    // Block the (0,0) landing cell of T spawn->half at (4,0);
    // SRS+ table must then take kick 1 = (0,1).
    f.rows[1] |= (@as(u128, 1) << 5);
    const r = tryRotate(&f, .t, .spawn, .half, 4, 0);
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u8, 1), r.kick_index);
    try std.testing.expectEqual(@as(i32, 4), r.x);
    try std.testing.expectEqual(@as(i32, 1), r.y);
}

test "180 kick I" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    // Block the (0,0) landing row of I spawn->half at (0,5);
    // SRS+ table must then take kick 3 = (0,1).
    f.rows[6] |= 0b1111;
    const r = tryRotate(&f, .i, .spawn, .half, 0, 5);
    try std.testing.expect(r.ok);
    try std.testing.expectEqual(@as(u8, 3), r.kick_index);
    try std.testing.expectEqual(@as(i32, 0), r.x);
    try std.testing.expectEqual(@as(i32, 6), r.y);
}

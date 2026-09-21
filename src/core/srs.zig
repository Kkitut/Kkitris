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

pub fn kickList(kind: PieceKind, from: Rotation, to: Rotation) [5]Kick {
    return switch (kind) {
        .o => .{ .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 }, .{ .dx = 0, .dy = 0 } },
        .i => iTable(from, to),
        else => jlstzTable(from, to),
    };
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

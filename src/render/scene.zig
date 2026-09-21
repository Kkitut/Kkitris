const std = @import("std");
const cell_mod = @import("../core/cell.zig");
const Cell = cell_mod.Cell;
const game_mod = @import("../core/game.zig");
const Game = game_mod.Game;
const piece_mod = @import("../core/piece.zig");

pub const Instance = struct {
    pos: [3]f32,
    scale: [3]f32,
    color: [4]f32,
    link: u4,
    ghost: bool = false,
};

pub const MAX_INSTANCES = 100 * 100 + 8;

pub fn buildScene(game: *const Game, out: []Instance) usize {
    var n: usize = 0;
    const w: usize = game.field.w;
    const h: usize = game.field.h;
    const wi: i32 = @intCast(game.field.w);
    const hi: i32 = @intCast(game.field.h);

    for (0..h) |y| {
        for (0..w) |x| {
            const c: Cell = game.field.cells[y * w + x];
            if (!c.occupied) continue;
            if (n >= out.len) return n;
            const rgb = c.mino.rgb();
            const link: u4 = @bitCast(c.link);
            out[n] = .{
                .pos = .{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5, 0 },
                .scale = .{ 0.95, 0.95, 0.95 },
                .color = .{ rgb[0], rgb[1], rgb[2], 1 },
                .link = link,
            };
            n += 1;
        }
    }

    if (!game.has_active) return n;

    const masks = game.activeMasks();
    const gy = game.ghostY();
    const grgb = game.active.kind.mino().rgb();
    for (masks, 0..) |row16, r| {
        var bits = row16;
        var lx: i32 = 0;
        while (bits != 0) : (lx += 1) {
            if (bits & 1 != 0) {
                const fx = game.active.x + lx;
                const fy = gy + @as(i32, @intCast(r));
                if (fx >= 0 and fx < wi and fy >= 0 and fy < hi and n < out.len) {
                    out[n] = .{
                        .pos = .{ @as(f32, @floatFromInt(fx)) + 0.5, @as(f32, @floatFromInt(fy)) + 0.5, 0 },
                        .scale = .{ 0.9, 0.9, 0.5 },
                        .color = .{ grgb[0], grgb[1], grgb[2], 0.25 },
                        .link = 0,
                        .ghost = true,
                    };
                    n += 1;
                }
            }
            bits >>= 1;
        }
    }

    const argb = game.active.kind.mino().rgb();
    for (masks, 0..) |row16, r| {
        var bits = row16;
        var lx: i32 = 0;
        while (bits != 0) : (lx += 1) {
            if (bits & 1 != 0) {
                const fx = game.active.x + lx;
                const fy = game.active.y + @as(i32, @intCast(r));
                if (fx >= 0 and fx < wi and fy >= 0 and fy < hi and n < out.len) {
                    out[n] = .{
                        .pos = .{ @as(f32, @floatFromInt(fx)) + 0.5, @as(f32, @floatFromInt(fy)) + 0.5, 0.15 },
                        .scale = .{ 0.95, 0.95, 0.95 },
                        .color = .{ argb[0], argb[1], argb[2], 1 },
                        .link = 0,
                    };
                    n += 1;
                }
            }
            bits >>= 1;
        }
    }
    return n;
}

test "scene" {
    const alloc = std.testing.allocator;
    var g = try Game.init(alloc, .{ .w = 10, .h = 40, .visible_h = 20, .endless = false });
    defer g.deinit();
    var buf: [MAX_INSTANCES]Instance = undefined;
    const n = buildScene(&g, &buf);
    try std.testing.expect(n >= 4);
}

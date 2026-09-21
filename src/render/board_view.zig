const std = @import("std");
const inst_mod = @import("instance.zig");
const InstanceData = inst_mod.InstanceData;
const Skin = inst_mod.Skin;
const push = inst_mod.push;
const font = @import("../ui/font.zig");
const game_mod = @import("../core/game.zig");
const Game = game_mod.Game;
const config_mod = @import("../core/config.zig");
const piece_mod = @import("../core/piece.zig");
const PieceKind = piece_mod.PieceKind;


pub const MenuSize = enum(u8) {
    tall = 0,
    classic = 1,

    pub fn dims(self: MenuSize) struct { w: u32, h: u32, visible: u32 } {
        return switch (self) {
            .tall => .{ .w = 10, .h = 40, .visible = 20 },
            .classic => .{ .w = 10, .h = 20, .visible = 20 },
        };
    }

    pub fn label(self: MenuSize) []const u8 {
        return switch (self) {
            .tall => "SIZE 10X40",
            .classic => "SIZE 10X20",
        };
    }
};

const WHITE = [4]f32{ 1, 1, 1, 1 };
const DIM = [4]f32{ 0.55, 0.58, 0.65, 1 };
const ACCENT = [4]f32{ 0.1, 0.9, 0.9, 1 };
const PANEL = [4]f32{ 0.07, 0.08, 0.11, 1 };
const PANEL_EDGE = [4]f32{ 0.25, 0.28, 0.35, 1 };

fn rect(list: []InstanceData, count: *usize, cx: f32, cy: f32, w: f32, h: f32, color: [4]f32, tex: u32) void {
    _ = push(list, count, .{
        .color = color,
        .position = .{ cx, cy },
        .scale = .{ w, h },
        .rotation = 0,
        .texture_index = tex,
    });
}

fn centeredText(list: []InstanceData, count: *usize, str: []const u8, cx: f32, y: f32, px: f32, color: [4]f32) void {
    const x = cx - font.textWidth(str, px) * 0.5;
    font.drawText(list, count, str, x, y, px, color);
}

fn centeredTextUp(list: []InstanceData, count: *usize, str: []const u8, cx: f32, y_top: f32, px: f32, color: [4]f32) void {
    const x = cx - font.textWidth(str, px) * 0.5;
    font.drawTextUp(list, count, str, x, y_top, px, color);
}


pub const MENU_ITEMS = [_][]const u8{ "START", "SETTINGS", "QUIT" };

pub fn renderSettings(
    list: []InstanceData,
    fbw: f32,
    fbh: f32,
    cfg: config_mod.RulesConfig,
    selected: usize,
) usize {
    var n: usize = 0;
    rect(list, &n, fbw * 0.5, fbh * 0.5, fbw, fbh, .{ 0.04, 0.045, 0.06, 1 }, Skin.white);

    const body_px: f32 = @max(3.0, fbw / 260.0);
    const cx = fbw * 0.5;
    centeredText(list, &n, "SETTINGS", cx, fbh * 0.5 - body_px * 22.0, body_px * 1.6, WHITE);

    var val_bufs: [4][16]u8 = undefined;
    const sdf_str = if (cfg.sdf > 40.0) "SDF INF" else std.fmt.bufPrint(&val_bufs[3], "SDF {d}X", .{@as(u32, @intFromFloat(cfg.sdf + 0.5))}) catch "SDF";
    const vals = [_][]const u8{
        std.fmt.bufPrint(&val_bufs[0], "DAS {d}MS", .{@as(u32, @intFromFloat(cfg.das_sec * 1000.0 + 0.5))}) catch "DAS",
        std.fmt.bufPrint(&val_bufs[1], "ARR {d}MS", .{@as(u32, @intFromFloat(cfg.arr_sec * 1000.0 + 0.5))}) catch "ARR",
        std.fmt.bufPrint(&val_bufs[2], "DCD {d}MS", .{@as(u32, @intFromFloat(cfg.dcd_sec * 1000.0 + 0.5))}) catch "DCD",
        sdf_str,
    };
    var y = fbh * 0.5 - body_px * 8.0;
    for (vals, 0..) |row, i| {
        const sel = selected == i;
        var line: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&line, "{s} {s} {s}", .{
            if (sel) ">" else " ",
            row,
            if (sel) "<" else " ",
        }) catch row;
        centeredText(list, &n, s, cx, y, body_px * 1.4, if (sel) WHITE else DIM);
        y += body_px * 8.0;
    }
    centeredText(
        list,
        &n,
        if (selected == 4) "> BACK <" else "  BACK  ",
        cx,
        y,
        body_px * 1.4,
        if (selected == 4) WHITE else DIM,
    );
    return n;
}

pub fn renderMenu(
    list: []InstanceData,
    fbw: f32,
    fbh: f32,
    selected: usize,
    time_sec: f32,
) usize {
    var n: usize = 0;
    rect(list, &n, fbw * 0.5, fbh * 0.5, fbw, fbh, .{ 0.04, 0.045, 0.06, 1 }, Skin.white);

    const body_px: f32 = @max(3.0, fbw / 260.0);
    const cx = fbw * 0.5;
    var y = fbh * 0.5 - body_px * 8.0;

    for (MENU_ITEMS, 0..) |item, i| {
        const blink = @sin(time_sec * 4.0) > -0.2;
        var buf: [16]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{s} {s} {s}", .{
            if (selected == i and blink) ">" else " ",
            item,
            if (selected == i and blink) "<" else " ",
        }) catch item;
        centeredText(list, &n, s, cx, y, body_px * 1.4, if (selected == i) WHITE else DIM);
        y += body_px * 8.0;
    }
    return n;
}


fn skinForActive(kind: PieceKind) u32 {
    return switch (kind) {
        .i => Skin.i,
        .o => Skin.o,
        .t => Skin.t,
        .s => Skin.s,
        .z => Skin.z,
        .j => Skin.j,
        .l => Skin.l,
    };
}

fn drawMinoCells(
    list: []InstanceData,
    count: *usize,
    masks: [4]u16,
    base_fx: i32,
    base_fy: i32,
    tex: u32,
    color: [4]f32,
) void {
    for (masks, 0..) |row16, r| {
        var bits = row16;
        var lx: i32 = 0;
        while (bits != 0) : (lx += 1) {
            if (bits & 1 != 0) {
                const fx = base_fx + lx;
                const fy = base_fy + @as(i32, @intCast(r));
                if (fy >= 0) {
                    const sx = @as(f32, @floatFromInt(fx)) + 0.5;
                    const sy = @as(f32, @floatFromInt(fy)) + 0.5;
                    rect(list, count, sx, sy, 0.96, 0.96, color, tex);
                }
            }
            bits >>= 1;
        }
    }
}

fn drawPreview(
    list: []InstanceData,
    count: *usize,
    kind: PieceKind,
    mino_tex: u32,
    color: [4]f32,
    box_cx: f32,
    box_cy: f32,
    box_w: f32,
    cell: f32,
) void {
    const masks = piece_mod.mask(kind, .spawn);
    var min_lx: i32 = 4;
    var max_lx: i32 = -1;
    var min_r: i32 = 4;
    var max_r: i32 = -1;
    for (masks, 0..) |row16, r| {
        var bits = row16;
        var lx: i32 = 0;
        while (bits != 0) : (lx += 1) {
            if (bits & 1 != 0) {
                min_lx = @min(min_lx, lx);
                max_lx = @max(max_lx, lx);
                min_r = @min(min_r, @as(i32, @intCast(r)));
                max_r = @max(max_r, @as(i32, @intCast(r)));
            }
            bits >>= 1;
        }
    }
    if (max_lx < 0) return;
    const pw = @as(f32, @floatFromInt(max_lx - min_lx + 1)) * cell;
    const ph = @as(f32, @floatFromInt(max_r - min_r + 1)) * cell;
    _ = box_w;
    const ox = box_cx - pw * 0.5;
    const oy = box_cy - ph * 0.5;
    for (masks, 0..) |row16, r| {
        var bits = row16;
        var lx: i32 = 0;
        while (bits != 0) : (lx += 1) {
            if (bits & 1 != 0) {
                const sx = ox + (@as(f32, @floatFromInt(lx - min_lx)) + 0.5) * cell;
                const sy = oy + (@as(f32, @floatFromInt(@as(i32, @intCast(r)) - min_r)) + 0.5) * cell;
                rect(list, count, sx, sy, cell * 0.94, cell * 0.94, color, mino_tex);
            }
            bits >>= 1;
        }
    }
}

pub const PANEL_MARGIN: f32 = 7.0;

pub fn renderPlay(list: []InstanceData, game: *const Game, time_sec: f32) usize {
    var n: usize = 0;
    _ = time_sec;

    const w: i32 = @intCast(game.field.w);
    const h: i32 = @intCast(game.field.h);
    const visible: i32 = @intCast(@min(game.cfg.visible_h, game.field.h));
    const wf: f32 = @floatFromInt(w);
    const vf: f32 = @floatFromInt(visible);

    rect(list, &n, wf * 0.5, vf * 0.5, wf + 0.6, vf + 0.6, PANEL_EDGE, Skin.white);
    rect(list, &n, wf * 0.5, vf * 0.5, wf, vf, PANEL, Skin.white);

    var fy: i32 = 0;
    while (fy < visible) : (fy += 1) {
        var fx: i32 = 0;
        while (fx < w) : (fx += 1) {
            const c = game.field.cells[@as(usize, @intCast(fy)) * @as(usize, @intCast(w)) + @as(usize, @intCast(fx))];
            if (!c.occupied) continue;
            const rgb = c.mino.rgb();
            rect(
                list,
                &n,
                @as(f32, @floatFromInt(fx)) + 0.5,
                @as(f32, @floatFromInt(fy)) + 0.5,
                0.96,
                0.96,
                .{ rgb[0], rgb[1], rgb[2], 1 },
                Skin.forMino(c.mino),
            );
        }
        if (fy == h - 1) break;
    }

    if (game.has_active) {
        const masks = game.activeMasks();
        const gy = game.ghostY();
        const tex = skinForActive(game.active.kind);
        const rgb = game.active.kind.mino().rgb();
        drawMinoCells(list, &n, masks, game.active.x, gy, tex, .{
            rgb[0],
            rgb[1],
            rgb[2],
            0.28,
        });
        drawMinoCells(
            list,
            &n,
            masks,
            game.active.x,
            game.active.y,
            tex,
            .{ rgb[0], rgb[1], rgb[2], 1 },
        );
    }

    const label_px: f32 = 0.26;
    const value_px: f32 = 0.34;
    const panel_w: f32 = 6.0;
    const hold_cx: f32 = -3.8;
    const next_cx: f32 = wf + 3.8;
    const panels_top: f32 = vf;

    const hold_h: f32 = 4.5;
    const hold_cy = panels_top - hold_h * 0.5;
    rect(list, &n, hold_cx, hold_cy, panel_w, hold_h, PANEL_EDGE, Skin.white);
    rect(list, &n, hold_cx, hold_cy, panel_w - 0.12, hold_h - 0.12, PANEL, Skin.white);
    centeredTextUp(list, &n, "HOLD", hold_cx, panels_top - 0.15, label_px, DIM);
    if (game.held) |held_kind| {
        const ghosted: [4]f32 = if (game.can_hold) .{ 1, 1, 1, 1 } else .{ 0.45, 0.45, 0.45, 1 };
        const rgb = held_kind.mino().rgb();
        drawPreview(
            list,
            &n,
            held_kind,
            skinForActive(held_kind),
            .{ rgb[0] * ghosted[0], rgb[1] * ghosted[1], rgb[2] * ghosted[2], 1 },
            hold_cx,
            hold_cy - 0.6,
            panel_w,
            0.55,
        );
    }

    const preview_n: usize = @min(@as(usize, game.cfg.preview_count), 5);
    const next_h = @as(f32, @floatFromInt(preview_n)) * 2.2 + 1.4;
    const next_cy = panels_top - next_h * 0.5;
    rect(list, &n, next_cx, next_cy, panel_w, next_h, PANEL_EDGE, Skin.white);
    rect(list, &n, next_cx, next_cy, panel_w - 0.12, next_h - 0.12, PANEL, Skin.white);
    centeredTextUp(list, &n, "NEXT", next_cx, panels_top - 0.15, label_px, DIM);
    var py = panels_top - 1.6;
    for (0..preview_n) |i| {
        const kind = game.bag.peek(i);
        const rgb = kind.mino().rgb();
        drawPreview(list, &n, kind, skinForActive(kind), .{ rgb[0], rgb[1], rgb[2], 1 }, next_cx, py - 0.9, panel_w, 0.55);
        py -= 2.2;
    }

    var ty = panels_top - hold_h - 0.5;
    var numbuf: [32]u8 = undefined;
    const stats = [_]struct { label: []const u8, value: u64 }{
        .{ .label = "SCORE", .value = game.score },
        .{ .label = "LINES", .value = game.lines_total },
        .{ .label = "LEVEL", .value = game.level },
    };
    for (stats) |st| {
        font.drawTextUp(list, &n, st.label, hold_cx - panel_w * 0.5, ty, label_px, DIM);
        ty -= label_px * 5.5;
        const s = std.fmt.bufPrint(&numbuf, "{d}", .{st.value}) catch "?";
        font.drawTextUp(list, &n, s, hold_cx - panel_w * 0.5, ty, value_px, WHITE);
        ty -= value_px * 8.0;
    }
    {
        const s = std.fmt.bufPrint(&numbuf, "B2B {s}", .{if (game.b2b) "ON" else "--"}) catch "B2B";
        font.drawTextUp(list, &n, s, hold_cx - panel_w * 0.5, ty, label_px, if (game.b2b) ACCENT else DIM);
        ty -= label_px * 6.0;
    }
    {
        const s = std.fmt.bufPrint(&numbuf, "SURGE {d}", .{game.surge}) catch "SURGE";
        font.drawTextUp(list, &n, s, hold_cx - panel_w * 0.5, ty, label_px, if (game.surge >= 4) ACCENT else DIM);
        ty -= label_px * 6.0;
    }
    if (game.cfg.endless and game.resets > 0) {
        const s = std.fmt.bufPrint(&numbuf, "RESET {d}", .{game.resets}) catch "RESET";
        font.drawTextUp(list, &n, s, hold_cx - panel_w * 0.5, ty, label_px, DIM);
    }

    return n;
}

test "renderplay" {
    const alloc = std.testing.allocator;
    var game = try Game.init(alloc, .{ .w = 10, .h = 40, .visible_h = 20 });
    defer game.deinit();
    var buf: [4096]InstanceData = undefined;
    const n = renderPlay(&buf, &game, 0);
    try std.testing.expect(n >= 4);
    for (buf[0..n]) |q| {
        for (q.position) |v| try std.testing.expect(std.math.isFinite(v));
    }
}

test "rendersettings" {
    var buf: [4096]InstanceData = undefined;
    const n = renderSettings(&buf, 1600, 900, .{}, 2);
    try std.testing.expect(n > 6);
    for (buf[0..n]) |q| {
        for (q.position) |v| try std.testing.expect(std.math.isFinite(v));
    }
}

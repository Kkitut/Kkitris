const std = @import("std");
const inst_mod = @import("../render/instance.zig");
const InstanceData = inst_mod.InstanceData;
const push = inst_mod.push;

pub const GLYPHS = struct {
    fn g(rows: [5]u3) [5]u3 {
        return rows;
    }

    pub fn get(ch: u8) [5]u3 {
        return switch (ch) {
            'A' => g(.{ 0b010, 0b101, 0b111, 0b101, 0b101 }),
            'B' => g(.{ 0b110, 0b101, 0b110, 0b101, 0b110 }),
            'C' => g(.{ 0b011, 0b100, 0b100, 0b100, 0b011 }),
            'D' => g(.{ 0b110, 0b101, 0b101, 0b101, 0b110 }),
            'E' => g(.{ 0b111, 0b100, 0b110, 0b100, 0b111 }),
            'F' => g(.{ 0b111, 0b100, 0b110, 0b100, 0b100 }),
            'G' => g(.{ 0b011, 0b100, 0b101, 0b101, 0b011 }),
            'H' => g(.{ 0b101, 0b101, 0b111, 0b101, 0b101 }),
            'I' => g(.{ 0b111, 0b010, 0b010, 0b010, 0b111 }),
            'J' => g(.{ 0b001, 0b001, 0b001, 0b101, 0b010 }),
            'K' => g(.{ 0b101, 0b101, 0b110, 0b101, 0b101 }),
            'L' => g(.{ 0b100, 0b100, 0b100, 0b100, 0b111 }),
            'M' => g(.{ 0b101, 0b111, 0b111, 0b101, 0b101 }),
            'N' => g(.{ 0b110, 0b101, 0b101, 0b101, 0b101 }),
            'O' => g(.{ 0b010, 0b101, 0b101, 0b101, 0b010 }),
            'P' => g(.{ 0b110, 0b101, 0b110, 0b100, 0b100 }),
            'Q' => g(.{ 0b010, 0b101, 0b101, 0b110, 0b011 }),
            'R' => g(.{ 0b110, 0b101, 0b110, 0b101, 0b101 }),
            'S' => g(.{ 0b011, 0b100, 0b010, 0b001, 0b110 }),
            'T' => g(.{ 0b111, 0b010, 0b010, 0b010, 0b010 }),
            'U' => g(.{ 0b101, 0b101, 0b101, 0b101, 0b111 }),
            'V' => g(.{ 0b101, 0b101, 0b101, 0b101, 0b010 }),
            'W' => g(.{ 0b101, 0b101, 0b111, 0b111, 0b101 }),
            'X' => g(.{ 0b101, 0b101, 0b010, 0b101, 0b101 }),
            'Y' => g(.{ 0b101, 0b101, 0b010, 0b010, 0b010 }),
            'Z' => g(.{ 0b111, 0b001, 0b010, 0b100, 0b111 }),
            '0' => g(.{ 0b111, 0b101, 0b101, 0b101, 0b111 }),
            '1' => g(.{ 0b010, 0b110, 0b010, 0b010, 0b111 }),
            '2' => g(.{ 0b111, 0b001, 0b111, 0b100, 0b111 }),
            '3' => g(.{ 0b111, 0b001, 0b111, 0b001, 0b111 }),
            '4' => g(.{ 0b101, 0b101, 0b111, 0b001, 0b001 }),
            '5' => g(.{ 0b111, 0b100, 0b111, 0b001, 0b111 }),
            '6' => g(.{ 0b111, 0b100, 0b111, 0b101, 0b111 }),
            '7' => g(.{ 0b111, 0b001, 0b001, 0b010, 0b010 }),
            '8' => g(.{ 0b111, 0b101, 0b111, 0b101, 0b111 }),
            '9' => g(.{ 0b111, 0b101, 0b111, 0b001, 0b111 }),
            '-' => g(.{ 0b000, 0b000, 0b111, 0b000, 0b000 }),
            '.' => g(.{ 0b000, 0b000, 0b000, 0b000, 0b010 }),
            ':' => g(.{ 0b000, 0b010, 0b000, 0b010, 0b000 }),
            '/' => g(.{ 0b001, 0b001, 0b010, 0b100, 0b100 }),
            '>' => g(.{ 0b100, 0b010, 0b001, 0b010, 0b100 }),
            '<' => g(.{ 0b001, 0b010, 0b100, 0b010, 0b001 }),
            '+' => g(.{ 0b000, 0b010, 0b111, 0b010, 0b000 }),
            '(' => g(.{ 0b001, 0b010, 0b010, 0b010, 0b001 }),
            ')' => g(.{ 0b100, 0b010, 0b010, 0b010, 0b100 }),
            else => g(.{ 0b000, 0b000, 0b000, 0b000, 0b000 }),
        };
    }
};

pub fn drawText(list: []InstanceData, count: *usize, str: []const u8, x: f32, y: f32, px: f32, color: [4]f32) void {
    var cx = x;
    for (str) |raw| {
        const ch: u8 = if (raw >= 'a' and raw <= 'z') raw - 32 else raw;
        if (ch == ' ') {
            cx += 4.0 * px;
            continue;
        }
        const glyph = GLYPHS.get(ch);
        for (glyph, 0..) |row, ry| {
            for (0..3) |rx| {
                if ((row >> @intCast(2 - rx)) & 1 == 0) continue;
                _ = push(list, count, .{
                    .color = color,
                    .position = .{
                        cx + (@as(f32, @floatFromInt(rx)) + 0.5) * px,
                        y + (@as(f32, @floatFromInt(ry)) + 0.5) * px,
                    },
                    .scale = .{ px, px },
                    .rotation = 0,
                    .texture_index = inst_mod.Skin.white,
                });
            }
        }
        cx += 4.0 * px;
    }
}

pub fn textWidth(str: []const u8, px: f32) f32 {
    return @as(f32, @floatFromInt(str.len)) * 4.0 * px - px;
}

pub fn drawTextUp(list: []InstanceData, count: *usize, str: []const u8, x: f32, y_top: f32, px: f32, color: [4]f32) void {
    var cx = x;
    for (str) |raw| {
        const ch: u8 = if (raw >= 'a' and raw <= 'z') raw - 32 else raw;
        if (ch == ' ') {
            cx += 4.0 * px;
            continue;
        }
        const glyph = GLYPHS.get(ch);
        for (glyph, 0..) |row, ry| {
            for (0..3) |rx| {
                if ((row >> @intCast(2 - rx)) & 1 == 0) continue;
                _ = push(list, count, .{
                    .color = color,
                    .position = .{
                        cx + (@as(f32, @floatFromInt(rx)) + 0.5) * px,
                        y_top - (@as(f32, @floatFromInt(ry)) + 0.5) * px,
                    },
                    .scale = .{ px, px },
                    .rotation = 0,
                    .texture_index = inst_mod.Skin.white,
                });
            }
        }
        cx += 4.0 * px;
    }
}

test "glyphs" {
    var filled: u32 = 0;
    for (GLYPHS.get('A')) |row| filled += @popCount(row);
    try std.testing.expect(filled > 0);
    var blank: u32 = 0;
    for (GLYPHS.get(' ')) |row| blank += @popCount(row);
    try std.testing.expectEqual(@as(u32, 0), blank);
}

test "drawtext" {
    var buf: [64]InstanceData = undefined;
    var n: usize = 0;
    drawText(&buf, &n, "A", 0, 0, 2, .{ 1, 1, 1, 1 });
    try std.testing.expect(n > 0);
    try std.testing.expectEqual(textWidth("A", 2), 3.0 * 2.0);
}

test "drawtext up" {
    var down_buf: [64]InstanceData = undefined;
    var up_buf: [64]InstanceData = undefined;
    var nd: usize = 0;
    var nu: usize = 0;
    drawText(&down_buf, &nd, "AB", 0, 0, 1, .{ 1, 1, 1, 1 });
    drawTextUp(&up_buf, &nu, "AB", 0, 0, 1, .{ 1, 1, 1, 1 });
    try std.testing.expectEqual(nd, nu);
    for (down_buf[0..nd], up_buf[0..nu]) |a, b| {
        try std.testing.expectEqual(a.position[0], b.position[0]);
        try std.testing.expectEqual(-a.position[1], b.position[1]);
    }
}

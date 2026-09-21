const std = @import("std");
const cell_mod = @import("cell.zig");
const Cell = cell_mod.Cell;
const BlockKind = cell_mod.BlockKind;
const MinoKind = cell_mod.MinoKind;
const piece_mod = @import("piece.zig");

pub const MAX_W = 100;
pub const MAX_H = 100;
pub const MIN_W = 1;
pub const MIN_H = 1;

pub const Field = struct {
    alloc: std.mem.Allocator,
    w: u32,
    h: u32,
    rows: []u128,
    cells: []Cell,

    pub fn init(alloc: std.mem.Allocator, w: u32, h: u32) !Field {
        std.debug.assert(w >= MIN_W and w <= MAX_W);
        std.debug.assert(h >= MIN_H and h <= MAX_H);
        const rows = try alloc.alloc(u128, h);
        @memset(rows, 0);
        const cells = try alloc.alloc(Cell, w * h);
        @memset(cells, Cell.EMPTY);
        return .{ .alloc = alloc, .w = w, .h = h, .rows = rows, .cells = cells };
    }

    pub fn deinit(self: *Field) void {
        self.alloc.free(self.rows);
        self.alloc.free(self.cells);
        self.* = undefined;
    }

    pub fn clear(self: *Field) void {
        @memset(self.rows, 0);
        @memset(self.cells, Cell.EMPTY);
    }

    inline fn idx(self: *const Field, x: u32, y: u32) usize {
        return @as(usize, y) * self.w + x;
    }

    pub fn get(self: *const Field, x: u32, y: u32) Cell {
        return self.cells[self.idx(x, y)];
    }

    pub fn fullMask(self: *const Field) u128 {
        if (self.w >= 128) return std.math.maxInt(u128);
        return (@as(u128, 1) << @intCast(self.w)) - 1;
    }

    pub fn collides(self: *const Field, masks: [4]u16, px: i32, py: i32) bool {
        const w: i32 = @intCast(self.w);
        const h: i32 = @intCast(self.h);
        for (masks, 0..) |row16, r| {
            if (row16 == 0) continue;
            const fy: i32 = py + @as(i32, @intCast(r));
            if (fy < 0) return true;
            if (fy >= h) continue;
            if (px < 0) {
                if (-px >= 4) return true;
                const s: u3 = @intCast(-px);
                const lost: u16 = row16 & (((@as(u16, 1) << s) - 1));
                if (lost != 0) return true;
                const bits: u128 = @as(u128, row16 >> s);
                if ((self.rows[@as(usize, @intCast(fy))] & bits) != 0) return true;
            } else {
                if (px >= w) return true;
                const s: u7 = @intCast(px);
                const bits: u128 = @as(u128, row16) << s;
                if ((bits >> @as(u7, @intCast(self.w))) != 0) return true;
                if ((self.rows[@as(usize, @intCast(fy))] & bits) != 0) return true;
            }
        }
        return false;
    }

    pub fn ghostY(self: *const Field, masks: [4]u16, px: i32, py: i32) i32 {
        var y = py;
        while (!self.collides(masks, px, y - 1)) y -= 1;
        return y;
    }


    pub const LockResult = struct {
        cells_written: u32,
        min_y: u32,
        max_y: u32,
    };

    pub fn lock(self: *Field, masks: [4]u16, px: i32, py: i32, kind: BlockKind, mino: MinoKind) LockResult {
        var n: u32 = 0;
        var min_y: u32 = self.h;
        var max_y: u32 = 0;
        for (masks, 0..) |row16, r| {
            var bits = row16;
            var lx: i32 = 0;
            while (bits != 0) : (lx += 1) {
                if (bits & 1 != 0) {
                    const fx = px + lx;
                    const fy = py + @as(i32, @intCast(r));
                    if (fx >= 0 and fx < @as(i32, @intCast(self.w)) and fy >= 0 and fy < @as(i32, @intCast(self.h))) {
                        const ux: u32 = @intCast(fx);
                        const uy: u32 = @intCast(fy);
                        self.cells[self.idx(ux, uy)] = Cell.make(kind, mino);
                        self.rows[uy] |= (@as(u128, 1) << @intCast(ux));
                        n += 1;
                        min_y = @min(min_y, uy);
                        max_y = @max(max_y, uy);
                    }
                }
                bits >>= 1;
            }
        }
        if (n > 0) self.refreshLinks(min_y, max_y);
        return .{ .cells_written = n, .min_y = min_y, .max_y = max_y };
    }

    pub fn clearLines(self: *Field, cleared_rows: ?[]u32) u32 {
        const full = self.fullMask();
        var write: u32 = 0;
        var cleared: u32 = 0;
        var y: u32 = 0;
        while (y < self.h) : (y += 1) {
            const is_full = (self.rows[y] & full) == full;
            if (!is_full) {
                if (write != y) {
                    self.rows[write] = self.rows[y];
                    const dst = @as(usize, write) * self.w;
                    const src = @as(usize, y) * self.w;
                    @memcpy(self.cells[dst .. dst + self.w], self.cells[src .. src + self.w]);
                }
                write += 1;
            } else {
                if (self.rowHasSolid(y)) {
                    if (write != y) {
                        self.rows[write] = self.rows[y];
                        const dst = @as(usize, write) * self.w;
                        const src = @as(usize, y) * self.w;
                        @memcpy(self.cells[dst .. dst + self.w], self.cells[src .. src + self.w]);
                    }
                    write += 1;
                } else {
                    if (cleared_rows) |out| {
                        if (cleared < out.len) out[cleared] = y;
                    }
                    cleared += 1;
                }
            }
        }
        var f = write;
        while (f < self.h) : (f += 1) {
            self.rows[f] = 0;
            const dst = @as(usize, f) * self.w;
            @memset(self.cells[dst .. dst + self.w], Cell.EMPTY);
        }
        if (cleared > 0) self.refreshLinks(0, self.h - 1);
        return cleared;
    }

    fn rowHasSolid(self: *const Field, y: u32) bool {
        const base = @as(usize, y) * self.w;
        for (self.cells[base .. base + self.w]) |c| {
            if (c.isSolid()) return true;
        }
        return false;
    }

    pub fn pushGarbageUp(self: *Field, count: u32, holes: []const u32) void {
        if (count == 0) return;
        const n: usize = @min(@as(usize, count), @as(usize, self.h));
        const w = @as(usize, self.w);
        const h = @as(usize, self.h);
        var y: usize = h;
        while (y > 0) {
            y -= 1;
            if (y + n < h) {
                self.rows[y + n] = self.rows[y];
                @memcpy(self.cells[(y + n) * w .. (y + n) * w + w], self.cells[y * w .. y * w + w]);
            }
            if (y == 0) break;
        }
        for (0..n) |i| {
            const hole: usize = if (holes.len > 0) @as(usize, holes[i % holes.len]) % w else 0;
            var bits: u128 = self.fullMask();
            bits &= ~(@as(u128, 1) << @intCast(hole));
            self.rows[i] = bits;
            for (0..w) |x| {
                self.cells[i * w + x] = if (x == hole) Cell.EMPTY else Cell.make(.garbage, .garbage);
            }
        }
        self.refreshLinks(0, self.h - 1);
    }

    pub fn refreshLinks(self: *Field, min_y: u32, max_y: u32) void {
        const lo: u32 = if (min_y > 0) min_y - 1 else 0;
        const hi: u32 = @min(max_y + 1, self.h - 1);
        var y = lo;
        while (y <= hi) : (y += 1) {
            for (0..self.w) |x| {
                const i = @as(usize, y) * self.w + x;
                var c = self.cells[i];
                if (!c.occupied) continue;
                var px = false;
                var nx = false;
                var py = false;
                var ny = false;
                if (x + 1 < self.w) px = self.cells[i + 1].occupied;
                if (x >= 1) nx = self.cells[i - 1].occupied;
                if (y + 1 < self.h) py = self.cells[@as(usize, y + 1) * self.w + x].occupied;
                if (y >= 1) ny = self.cells[@as(usize, y - 1) * self.w + x].occupied;
                c.link = .{ .px = px, .nx = nx, .py = py, .ny = ny };
                self.cells[i] = c;
            }
            if (y == self.h - 1) break;
        }
    }

    pub fn hash(self: *const Field) u64 {
        var hsh: u64 = 0xcbf29ce484222325;
        for (self.rows) |r| {
            const b = std.mem.asBytes(&r);
            for (b) |byte| {
                hsh ^= byte;
                hsh *%= 0x100000001b3;
            }
        }
        return hsh;
    }
};

test "collide" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    const m = piece_mod.MASKS[@intFromEnum(piece_mod.PieceKind.o)][0];
    try std.testing.expect(f.collides(m, 4, -3));
    try std.testing.expect(!f.collides(m, 4, 0));
    try std.testing.expect(f.collides(m, -2, 0));
    try std.testing.expect(f.collides(m, 9, 0));
}

test "lock" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 10, 40);
    defer f.deinit();
    const m = piece_mod.MASKS[@intFromEnum(piece_mod.PieceKind.o)][0];
    _ = f.lock(m, 4, 0, .normal, .o);
    try std.testing.expect(f.collides(m, 4, 0));
    try std.testing.expect(f.get(5, 2).occupied);
    try std.testing.expect(f.get(5, 2).link.px);
    try std.testing.expect(f.get(6, 2).link.nx);
}

test "clear" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 4, 4);
    defer f.deinit();
    const m = piece_mod.MASKS[@intFromEnum(piece_mod.PieceKind.i)][0];
    _ = f.lock(m, 0, 0, .normal, .i);
    try std.testing.expectEqual(@as(u32, 1), f.clearLines(null));
}

test "solid" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 4, 2);
    defer f.deinit();
    for (0..4) |x| {
        f.cells[@as(usize, 0) * 4 + x] = Cell.make(.solid, .garbage);
        f.rows[0] |= (@as(u128, 1) << @intCast(x));
    }
    try std.testing.expectEqual(@as(u32, 0), f.clearLines(null));
}

test "garbage" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, 4, 4);
    defer f.deinit();
    const holes = [_]u32{1};
    f.pushGarbageUp(1, &holes);
    try std.testing.expect(!f.get(1, 0).occupied);
    try std.testing.expect(f.get(0, 0).occupied);
    try std.testing.expectEqual(BlockKind.garbage, f.get(0, 0).kind);
}

test "sizes" {
    const alloc = std.testing.allocator;
    var big = try Field.init(alloc, 100, 100);
    defer big.deinit();
    try std.testing.expectEqual(@as(u32, 100), big.w);
    var tiny = try Field.init(alloc, 4, 1);
    defer tiny.deinit();
    try std.testing.expectEqual(@as(u32, 1), tiny.h);
}

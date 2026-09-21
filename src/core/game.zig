const std = @import("std");
const cell_mod = @import("cell.zig");
const BlockKind = cell_mod.BlockKind;
const field_mod = @import("field.zig");
const Field = field_mod.Field;
const piece_mod = @import("piece.zig");
const PieceKind = piece_mod.PieceKind;
const Rotation = piece_mod.Rotation;
const srs_mod = @import("srs.zig");
const bag_mod = @import("bag.zig");
const Bag = bag_mod.Bag;
const config_mod = @import("config.zig");
const RulesConfig = config_mod.RulesConfig;

pub const Buttons = packed struct(u16) {
    left: bool = false,
    right: bool = false,
    soft: bool = false,
    _pad: u13 = 0,
};

pub const Action = enum {
    none,
    move_left,
    move_right,
    soft_step,
    rotate_cw,
    rotate_ccw,
    rotate_180,
    hard_drop,
    hold,
};

pub const GameEvent = union(enum) {
    spawn: PieceKind,
    lock: struct { kind: PieceKind, cells: u32 },
    clear: struct { lines: u32, attack: u32, combo: i32, b2b: bool },
    tspin: struct { lines: u32, kick: u8 },
    hold: PieceKind,
    level_up: u32,
    over,
    endless_reset: u32,
};

pub const Active = struct {
    kind: PieceKind,
    rot: Rotation,
    x: i32,
    y: i32,
};

const MAX_EVENTS = 64;

pub const Game = struct {
    alloc: std.mem.Allocator,
    cfg: RulesConfig,
    field: Field,
    bag: Bag,
    active: Active,
    has_active: bool = false,
    held: ?PieceKind = null,
    can_hold: bool = true,

    fall_acc: f32 = 0,
    lock_timer: f32 = 0,
    lock_resets: u32 = 0,
    are_timer: f32 = 0,
    das_timer: f32 = 0,
    arr_acc: f32 = 0,
    das_dir: i32 = 0,

    score: u64 = 0,
    level: u32 = 1,
    lines_total: u32 = 0,
    combo: i32 = -1,
    b2b: bool = false,
    pieces: u64 = 0,
    attack_pending: u32 = 0,
    resets: u32 = 0,
    is_over: bool = false,

    last_was_rotate: bool = false,
    last_kick: u8 = 0,

    events: [MAX_EVENTS]GameEvent = undefined,
    event_count: usize = 0,

    pub fn init(alloc: std.mem.Allocator, cfg: RulesConfig) !Game {
        try cfg.validate();
        var g = Game{
            .alloc = alloc,
            .cfg = cfg,
            .field = try Field.init(alloc, cfg.w, cfg.h),
            .bag = Bag.init(cfg.seed),
            .active = .{ .kind = .t, .rot = .spawn, .x = 0, .y = 0 },
            .level = cfg.start_level,
        };
        g.start();
        return g;
    }

    pub fn deinit(self: *Game) void {
        self.field.deinit();
    }

    pub fn restart(self: *Game, seed: u64) void {
        self.field.clear();
        self.bag = Bag.init(seed);
        self.held = null;
        self.can_hold = true;
        self.fall_acc = 0;
        self.lock_timer = 0;
        self.lock_resets = 0;
        self.das_timer = 0;
        self.arr_acc = 0;
        self.das_dir = 0;
        self.score = 0;
        self.level = self.cfg.start_level;
        self.lines_total = 0;
        self.combo = -1;
        self.b2b = false;
        self.pieces = 0;
        self.attack_pending = 0;
        self.is_over = false;
        self.last_was_rotate = false;
        self.last_kick = 0;
        self.event_count = 0;
        self.start();
    }

    fn pushEvent(self: *Game, ev: GameEvent) void {
        if (self.event_count < MAX_EVENTS) {
            self.events[self.event_count] = ev;
            self.event_count += 1;
        }
    }

    pub fn drainEvents(self: *Game) []GameEvent {
        const out = self.events[0..self.event_count];
        self.event_count = 0;
        return out;
    }

    fn start(self: *Game) void {
        self.spawnNext();
    }

    fn spawnX(self: *const Game) i32 {
        const w: i32 = @intCast(self.cfg.w);
        return @divFloor(w - 4, 2);
    }

    fn spawnY(self: *const Game) i32 {
        const vis: i32 = @intCast(@min(self.cfg.visible_h, self.field.h));
        return @max(vis - 4, 0);
    }

    fn spawnNext(self: *Game) void {
        const kind = self.bag.next();
        const x = self.spawnX();
        const y = self.spawnY();
        const masks = piece_mod.mask(kind, .spawn);
        self.active = .{ .kind = kind, .rot = .spawn, .x = x, .y = y };
        self.has_active = true;
        self.fall_acc = 0;
        self.lock_timer = 0;
        self.lock_resets = 0;
        self.are_timer = self.cfg.are_sec;
        self.last_was_rotate = false;
        self.last_kick = 0;
        if (self.field.collides(masks, x, y)) {
            self.onGameOver();
        } else {
            self.pushEvent(.{ .spawn = kind });
        }
    }

    fn onGameOver(self: *Game) void {
        if (self.cfg.endless) {
            self.resets += 1;
            self.field.clear();
            self.can_hold = true;
            self.pushEvent(.{ .endless_reset = self.resets });
            const kind = self.active.kind;
            const x = self.spawnX();
            const y = self.spawnY();
            const masks = piece_mod.mask(kind, .spawn);
            if (self.field.collides(masks, x, y)) {
                self.is_over = true;
                self.pushEvent(.over);
            } else {
                self.fall_acc = 0;
                self.lock_timer = 0;
                self.lock_resets = 0;
                self.are_timer = self.cfg.are_sec;
                self.pushEvent(.{ .spawn = kind });
            }
        } else {
            self.is_over = true;
            self.has_active = false;
            self.pushEvent(.over);
        }
    }

    pub fn activeMasks(self: *const Game) [4]u16 {
        return piece_mod.mask(self.active.kind, self.active.rot);
    }

    pub fn ghostY(self: *const Game) i32 {
        return self.field.ghostY(self.activeMasks(), self.active.x, self.active.y);
    }

    fn onGround(self: *const Game) bool {
        return self.field.collides(self.activeMasks(), self.active.x, self.active.y - 1);
    }

    fn noteSuccessfulShift(self: *Game) void {
        if (self.onGround() and self.lock_resets < self.cfg.max_lock_resets) {
            self.lock_timer = 0;
            self.lock_resets += 1;
        }
        self.fall_acc = 0;
    }

    pub fn doAction(self: *Game, a: Action) void {
        if (self.is_over or !self.has_active) return;
        switch (a) {
            .none => {},
            .move_left => {
                if (!self.field.collides(self.activeMasks(), self.active.x - 1, self.active.y)) {
                    self.active.x -= 1;
                    self.last_was_rotate = false;
                    self.noteSuccessfulShift();
                }
            },
            .move_right => {
                if (!self.field.collides(self.activeMasks(), self.active.x + 1, self.active.y)) {
                    self.active.x += 1;
                    self.last_was_rotate = false;
                    self.noteSuccessfulShift();
                }
            },
            .soft_step => {
                if (!self.field.collides(self.activeMasks(), self.active.x, self.active.y - 1)) {
                    self.active.y -= 1;
                    self.score += 1;
                    self.last_was_rotate = false;
                } else {
                    self.lockNow();
                }
            },
            .rotate_cw => self.doRotate(self.active.rot.cw()),
            .rotate_ccw => self.doRotate(self.active.rot.ccw()),
            .rotate_180 => self.doRotate(self.active.rot.half_turn()),
            .hard_drop => {
                const gy = self.ghostY();
                const dist: u64 = @intCast(@max(self.active.y - gy, 0));
                self.active.y = gy;
                self.score += dist * 2;
                self.last_was_rotate = false;
                self.lockNow();
            },
            .hold => self.doHold(),
        }
    }

    fn doRotate(self: *Game, to: Rotation) void {
        const r = srs_mod.tryRotate(&self.field, self.active.kind, self.active.rot, to, self.active.x, self.active.y);
        if (r.ok) {
            self.active.x = r.x;
            self.active.y = r.y;
            self.active.rot = r.rot;
            self.last_was_rotate = true;
            self.last_kick = r.kick_index;
            self.noteSuccessfulShift();
        }
    }

    fn doHold(self: *Game) void {
        if (!self.cfg.hold_enabled or !self.can_hold) return;
        const cur = self.active.kind;
        if (self.held) |h| {
            self.held = cur;
            const x = self.spawnX();
            const y = self.spawnY();
            self.active = .{ .kind = h, .rot = .spawn, .x = x, .y = y };
            self.fall_acc = 0;
            self.lock_timer = 0;
            self.lock_resets = 0;
            self.are_timer = self.cfg.are_sec;
            self.last_was_rotate = false;
            if (self.field.collides(self.activeMasks(), x, y)) {
                self.onGameOver();
                return;
            }
        } else {
            self.held = cur;
            self.spawnNext();
        }
        self.can_hold = false;
        self.pushEvent(.{ .hold = cur });
    }

    pub fn tick(self: *Game, dt: f32, held: Buttons) void {
        if (self.is_over or !self.has_active) return;
        const step = @min(dt, 0.25);

        const want_dir: i32 = if (held.left and !held.right) -1 else if (held.right and !held.left) 1 else 0;
        if (want_dir == 0) {
            self.das_dir = 0;
            self.das_timer = 0;
            self.arr_acc = 0;
        } else {
            if (want_dir != self.das_dir) {
                self.das_dir = want_dir;
                self.das_timer = 0;
                self.arr_acc = 0;
                if (want_dir < 0) self.doAction(.move_left) else self.doAction(.move_right);
            } else {
                self.das_timer += step;
                if (self.das_timer >= self.cfg.das_sec) {
                    self.arr_acc += step;
                    while (self.arr_acc >= self.cfg.arr_sec) {
                        self.arr_acc -= self.cfg.arr_sec;
                        if (want_dir < 0) self.doAction(.move_left) else self.doAction(.move_right);
                        if (self.is_over or !self.has_active) return;
                    }
                }
            }
        }

        if (self.are_timer > 0) {
            self.are_timer -= step;
            return;
        }

        var interval = RulesConfig.gravityInterval(self.level);
        if (held.soft) interval /= self.cfg.soft_factor;
        self.fall_acc += step;
        while (self.fall_acc >= interval) {
            self.fall_acc -= interval;
            if (!self.field.collides(self.activeMasks(), self.active.x, self.active.y - 1)) {
                self.active.y -= 1;
                self.last_was_rotate = false;
                if (held.soft) self.score += 1;
            } else {
                break;
            }
        }

        if (self.onGround()) {
            self.lock_timer += step;
            if (self.lock_timer >= self.cfg.lock_delay_sec) self.lockNow();
        } else {
            self.lock_timer = 0;
        }
    }

    fn isTspin(self: *const Game) bool {
        if (!self.last_was_rotate or self.active.kind != .t) return false;
        if (self.last_kick == 0) {
        }
        const cx = self.active.x + 1;
        const cy = self.active.y + 1;
        var corners: u32 = 0;
        const pts = [_][2]i32{ .{ cx - 1, cy + 1 }, .{ cx + 1, cy + 1 }, .{ cx - 1, cy - 1 }, .{ cx + 1, cy - 1 } };
        for (pts) |p| {
            if (self.occupiedOrWall(p[0], p[1])) corners += 1;
        }
        return corners >= 3;
    }

    fn occupiedOrWall(self: *const Game, x: i32, y: i32) bool {
        if (x < 0 or x >= @as(i32, @intCast(self.cfg.w))) return true;
        if (y < 0) return true;
        if (y >= @as(i32, @intCast(self.cfg.h))) return false;
        const row = self.field.rows[@as(usize, @intCast(y))];
        return ((row >> @as(u7, @intCast(x))) & 1) != 0;
    }

    fn lockNow(self: *Game) void {
        if (!self.has_active) return;
        const kind = self.active.kind;
        const masks = self.activeMasks();
        const tspin = self.isTspin();
        const res = self.field.lock(masks, self.active.x, self.active.y, .normal, kind.mino());
        self.pushEvent(.{ .lock = .{ .kind = kind, .cells = res.cells_written } });
        self.pieces += 1;
        self.can_hold = true;

        if (res.cells_written == 0) {
            self.onGameOver();
            return;
        }

        var cleared_buf: [100]u32 = undefined;
        const n = self.field.clearLines(cleared_buf[0..@min(cleared_buf.len, @as(usize, self.cfg.h))]);

        if (n > 0) {
            self.combo += 1;
            const lv: f32 = @floatFromInt(self.level);
            var gained: u64 = 0;
            if (tspin) {
                const base: [5]u64 = .{ 400, 800, 1200, 1600, 2000 };
                gained = base[@min(n, 4)] * @as(u64, @intFromFloat(lv));
                self.pushEvent(.{ .tspin = .{ .lines = n, .kick = self.last_kick } });
            } else {
                const base: [5]u64 = .{ 0, 100, 300, 500, 800 };
                gained = base[@min(n, 4)] * @as(u64, @intFromFloat(lv));
            }
            const is_b2b_event = (n == 4 or tspin);
            if (is_b2b_event and self.b2b) gained = gained * 3 / 2;
            if (self.combo > 0) gained += @as(u64, @intCast(self.combo)) * 50 * @as(u64, @intFromFloat(lv));
            self.score += gained;

            const atk_table: [5]u32 = .{ 0, 0, 1, 2, 4 };
            var atk = atk_table[@min(n, 4)];
            if (is_b2b_event and self.b2b) atk += 1;
            if (tspin) atk += @min(n, 4);
            self.attack_pending += atk;
            self.b2b = is_b2b_event;

            self.lines_total += n;
            const new_level = self.cfg.start_level + self.lines_total / self.cfg.lines_per_level;
            if (new_level != self.level) {
                self.level = new_level;
                self.pushEvent(.{ .level_up = new_level });
            }
            self.pushEvent(.{ .clear = .{ .lines = n, .attack = atk, .combo = self.combo, .b2b = self.b2b } });
        } else {
            self.combo = -1;
        }
        self.spawnNext();
    }

    pub fn applyAttack(self: *Game, lines: u32, hole: u32) void {
        if (lines == 0 or self.is_over) return;
        var holes: [32]u32 = undefined;
        const n = @min(@as(usize, lines), holes.len);
        for (0..n) |i| holes[i] = hole + @as(u32, @intCast(i));
        self.field.pushGarbageUp(lines, holes[0..n]);
        if (self.has_active and self.field.collides(self.activeMasks(), self.active.x, self.active.y)) {
            var up: i32 = 0;
            while (up < 4 and self.field.collides(self.activeMasks(), self.active.x, self.active.y + up)) : (up += 1) {}
            self.active.y += up;
        }
    }

    pub fn takeAttack(self: *Game) u32 {
        const a = self.attack_pending;
        self.attack_pending = 0;
        return a;
    }

    pub fn hash(self: *const Game) u64 {
        var h: u64 = self.field.hash();
        const ax: u64 = @bitCast(@as(i64, self.active.x));
        const ay: u64 = @bitCast(@as(i64, self.active.y));
        h ^= ax *% 0x9e3779b97f4a7c15;
        h ^= ay *% 0xbf58476d1ce4e5b9;
        h ^= (@as(u64, @intFromEnum(self.active.kind)) << 32) ^ (@as(u64, @intFromEnum(self.active.rot)) << 40);
        h ^= self.bag.bags_drawn *% 0x94d049bb133111eb;
        h ^= self.score ^ (self.pieces << 1);
        return h;
    }
};

test "harddrop" {
    const alloc = std.testing.allocator;
    var g = try Game.init(alloc, .{ .w = 10, .h = 40, .visible_h = 20, .endless = false });
    defer g.deinit();
    const first = g.active.kind;
    g.doAction(.hard_drop);
    try std.testing.expectEqual(@as(u64, 1), g.pieces);
    _ = first;
    try std.testing.expect(g.has_active);
}

test "lineclear" {
    const alloc = std.testing.allocator;
    var g = try Game.init(alloc, .{ .w = 4, .h = 6, .visible_h = 6, .endless = false });
    defer g.deinit();
    for (0..4) |x| {
        g.field.cells[x] = cell_mod.Cell.make(.normal, .s);
        g.field.rows[0] |= (@as(u128, 1) << @intCast(x));
    }
    const before = g.lines_total;
    g.doAction(.hard_drop);
    try std.testing.expect(g.lines_total > before);
    try std.testing.expect(g.score > 0);
}

test "endless" {
    const alloc = std.testing.allocator;
    var g = try Game.init(alloc, .{ .w = 4, .h = 1, .visible_h = 1, .endless = true });
    defer g.deinit();
    for (0..4) |x| {
        g.field.cells[x] = cell_mod.Cell.make(.normal, .s);
        g.field.rows[0] |= (@as(u128, 1) << @intCast(x));
    }
    g.spawnNext();
    try std.testing.expect(g.resets >= 1);
    try std.testing.expect(!g.is_over);
}

test "spawn pos" {
    const alloc = std.testing.allocator;
    var g = try Game.init(alloc, .{ .w = 10, .h = 40, .visible_h = 20, .endless = false });
    defer g.deinit();
    try std.testing.expectEqual(@as(i32, 16), g.active.y);
    try std.testing.expect(g.has_active);
}

test "are" {
    const alloc = std.testing.allocator;
    var g = try Game.init(alloc, .{ .w = 10, .h = 40, .visible_h = 20, .endless = false });
    defer g.deinit();
    const y0 = g.active.y;
    const x0 = g.active.x;
    g.tick(0.1, .{});
    try std.testing.expectEqual(y0, g.active.y);
    g.doAction(.move_left);
    try std.testing.expectEqual(x0 - 1, g.active.x);
    g.tick(0.09, .{});
    try std.testing.expectEqual(y0, g.active.y);
    var i: usize = 0;
    while (i < 8) : (i += 1) g.tick(0.25, .{});
    try std.testing.expect(g.active.y < y0);
}

test "hash" {
    const alloc = std.testing.allocator;
    var a = try Game.init(alloc, .{ .seed = 42, .endless = false });
    defer a.deinit();
    var b = try Game.init(alloc, .{ .seed = 42, .endless = false });
    defer b.deinit();
    const acts = [_]Action{ .move_left, .rotate_cw, .hard_drop, .move_right, .hard_drop };
    for (acts) |x| {
        a.doAction(x);
        b.doAction(x);
    }
    try std.testing.expectEqual(a.hash(), b.hash());
}

test "reseed" {
    const alloc = std.testing.allocator;
    var g = try Game.init(alloc, .{ .seed = 42, .endless = false });
    defer g.deinit();
    const first = g.active.kind;
    g.restart(42);
    try std.testing.expectEqual(first, g.active.kind);
    var seen = [_]bool{false} ** 7;
    seen[@intFromEnum(first)] = true;
    var s: u64 = 43;
    while (s < 60) : (s += 1) {
        g.restart(s);
        seen[@intFromEnum(g.active.kind)] = true;
    }
    var distinct: u32 = 0;
    for (seen) |b| {
        if (b) distinct += 1;
    }
    try std.testing.expect(distinct > 1);
}

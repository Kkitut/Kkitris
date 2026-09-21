const std = @import("std");
const camera = @import("camera.zig");

pub const SENSITIVITY: f32 = 0.0025;
pub const MOVE_SPEED: f32 = 12.0;
pub const MAX_PITCH: f32 = std.math.pi * 0.5 - 0.01;

pub const Keys = struct {
    w: bool = false,
    a: bool = false,
    s: bool = false,
    d: bool = false,
    q: bool = false,
    e: bool = false,
    arr_up: bool = false,
    arr_down: bool = false,
    arr_left: bool = false,
    arr_right: bool = false,
};

pub const Freecam = struct {
    active: bool = false,
    pos: [3]f32 = .{ 0, 0, 0 },
    yaw: f32 = 0,
    pitch: f32 = 0,
    keys: Keys = .{},
    mouse_init: bool = false,
    last_x: f64 = 0,
    last_y: f64 = 0,

    pub fn resetToDefault(self: *Freecam, eye: [3]f32, center: [3]f32) void {
        self.pos = eye;
        const yp = camera.yawPitchFor(eye, center);
        self.yaw = yp.yaw;
        self.pitch = yp.pitch;
        self.keys = .{};
        self.mouse_init = false;
    }

    pub fn applyMouse(self: *Freecam, x: f64, y: f64) void {
        if (!self.mouse_init) {
            self.last_x = x;
            self.last_y = y;
            self.mouse_init = true;
            return;
        }
        const dx: f32 = @floatCast(x - self.last_x);
        const dy: f32 = @floatCast(y - self.last_y);
        self.last_x = x;
        self.last_y = y;
        self.yaw -= dx * SENSITIVITY;
        self.pitch -= dy * SENSITIVITY;
        self.pitch = std.math.clamp(self.pitch, -MAX_PITCH, MAX_PITCH);
    }

    pub fn forward(self: *const Freecam) [3]f32 {
        const cp = @cos(self.pitch);
        return .{ -@sin(self.yaw) * cp, @sin(self.pitch), -@cos(self.yaw) * cp };
    }

    pub fn update(self: *Freecam, dt: f32) void {
        const f = self.forward();
        var right = [3]f32{ -f[2], 0, f[0] };
        const rl = @sqrt(right[0] * right[0] + right[2] * right[2]);
        if (rl > 1e-6) {
            right[0] /= rl;
            right[2] /= rl;
        }
        var v = [3]f32{ 0, 0, 0 };
        if (self.keys.w or self.keys.arr_up) {
            v[0] += f[0];
            v[1] += f[1];
            v[2] += f[2];
        }
        if (self.keys.s or self.keys.arr_down) {
            v[0] -= f[0];
            v[1] -= f[1];
            v[2] -= f[2];
        }
        if (self.keys.d or self.keys.arr_right) {
            v[0] += right[0];
            v[2] += right[2];
        }
        if (self.keys.a or self.keys.arr_left) {
            v[0] -= right[0];
            v[2] -= right[2];
        }
        if (self.keys.e) v[1] += 1;
        if (self.keys.q) v[1] -= 1;
        const step = MOVE_SPEED * dt;
        self.pos[0] += v[0] * step;
        self.pos[1] += v[1] * step;
        self.pos[2] += v[2] * step;
    }

    pub fn viewProj(self: *const Freecam, proj: camera.Mat4) camera.Mat4 {
        const f = self.forward();
        const view = camera.lookAt(self.pos, .{
            self.pos[0] + f[0],
            self.pos[1] + f[1],
            self.pos[2] + f[2],
        }, .{ 0, 1, 0 });
        return camera.mul(proj, view);
    }
};

test "reset" {
    var fc = Freecam{};
    const eye = [3]f32{ 5, 8, 30 };
    const center = [3]f32{ 5, 10, 0 };
    fc.resetToDefault(eye, center);
    try std.testing.expectEqual(eye, fc.pos);
    const f = fc.forward();
    const want = [3]f32{ center[0] - eye[0], center[1] - eye[1], center[2] - eye[2] };
    const len = @sqrt(want[0] * want[0] + want[1] * want[1] + want[2] * want[2]);
    try std.testing.expectApproxEqAbs(want[0] / len, f[0], 1e-5);
    try std.testing.expectApproxEqAbs(want[1] / len, f[1], 1e-5);
    try std.testing.expectApproxEqAbs(want[2] / len, f[2], 1e-5);
}

test "mouselook" {
    var fc = Freecam{};
    fc.yaw = 0;
    fc.pitch = 0;
    fc.applyMouse(100, 100);
    fc.applyMouse(200, 100);
    try std.testing.expect(fc.yaw < 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), fc.pitch, 1e-6);
}

test "pitch" {
    var fc = Freecam{};
    fc.applyMouse(0, 0);
    fc.applyMouse(0, -100000);
    try std.testing.expect(fc.pitch <= MAX_PITCH);
    try std.testing.expect(fc.pitch > 0);
}

test "arrows" {
    var a = Freecam{};
    var b = Freecam{};
    a.keys.w = true;
    b.keys.arr_up = true;
    a.update(1.0);
    b.update(1.0);
    try std.testing.expectEqual(a.pos, b.pos);
    a.keys.w = false;
    a.keys.a = true;
    b.keys.arr_up = false;
    b.keys.arr_left = true;
    a.update(1.0);
    b.update(1.0);
    try std.testing.expectEqual(a.pos, b.pos);
}

test "move" {
    var fc = Freecam{};
    fc.yaw = 0;
    fc.pitch = 0;
    fc.keys.w = true;
    fc.update(1.0);
    try std.testing.expect(fc.pos[2] < 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), fc.pos[0], 1e-5);

    fc.keys.w = false;
    fc.keys.e = true;
    const y0 = fc.pos[1];
    fc.update(1.0);
    try std.testing.expect(fc.pos[1] > y0);
}

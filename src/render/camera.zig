const std = @import("std");

pub const DEFAULT_FOV_Y_DEG: f32 = 70.0;
pub const DEFAULT_NEAR: f32 = 0.1;
pub const DEFAULT_FAR: f32 = 200.0;

pub const Mat4 = [16]f32;

pub fn perspective(fov_y_deg: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const fov_rad = fov_y_deg * std.math.pi / 180.0;
    const f = 1.0 / @tan(fov_rad * 0.5);
    var m = [_]f32{0} ** 16;
    m[0] = f / aspect;
    m[5] = -f;
    m[10] = -far / (far - near);
    m[11] = -1.0;
    m[14] = -far * near / (far - near);
    return m;
}

pub fn projectClip(m: Mat4, p: [3]f32) ?[4]f32 {
    const x = m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12];
    const y = m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13];
    const z = m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14];
    const w = m[3] * p[0] + m[7] * p[1] + m[11] * p[2] + m[15];
    if (w <= 0) return null;
    return .{ x, y, z, w };
}

pub fn projectNdc(m: Mat4, p: [3]f32) ?[3]f32 {
    const clip = projectClip(m, p) orelse return null;
    return .{ clip[0] / clip[3], clip[1] / clip[3], clip[2] / clip[3] };
}

pub fn lookAt(eye: [3]f32, center: [3]f32, up: [3]f32) Mat4 {
    var f = [3]f32{ center[0] - eye[0], center[1] - eye[1], center[2] - eye[2] };
    const fl = @sqrt(f[0] * f[0] + f[1] * f[1] + f[2] * f[2]);
    f = .{ f[0] / fl, f[1] / fl, f[2] / fl };
    var s = [3]f32{
        f[1] * up[2] - f[2] * up[1],
        f[2] * up[0] - f[0] * up[2],
        f[0] * up[1] - f[1] * up[0],
    };
    const sl = @sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2]);
    s = .{ s[0] / sl, s[1] / sl, s[2] / sl };
    const u = [3]f32{
        s[1] * f[2] - s[2] * f[1],
        s[2] * f[0] - s[0] * f[2],
        s[0] * f[1] - s[1] * f[0],
    };
    return .{
        s[0], u[0], -f[0], 0,
        s[1], u[1], -f[1], 0,
        s[2], u[2], -f[2], 0,
        -(s[0] * eye[0] + s[1] * eye[1] + s[2] * eye[2]),
        -(u[0] * eye[0] + u[1] * eye[1] + u[2] * eye[2]),
        (f[0] * eye[0] + f[1] * eye[1] + f[2] * eye[2]),
        1,
    };
}

pub fn mul(a: Mat4, b: Mat4) Mat4 {
    var out = [_]f32{0} ** 16;
    for (0..4) |c| {
        for (0..4) |r| {
            var s: f32 = 0;
            for (0..4) |k| s += a[@as(usize, k) * 4 + r] * b[@as(usize, c) * 4 + k];
            out[@as(usize, c) * 4 + r] = s;
        }
    }
    return out;
}

pub const FitView = struct {
    eye: [3]f32,
    center: [3]f32,
    view: Mat4,
    proj: Mat4,
    view_proj: Mat4,
};

pub fn fitBoard(w_cells: u32, h_cells: u32, aspect: f32, tilt_deg: f32, fov_y_deg: f32) FitView {
    const w: f32 = @floatFromInt(w_cells);
    const h: f32 = @floatFromInt(h_cells);
    const cx = w * 0.5;
    const cy = h * 0.5;
    const fov_rad = fov_y_deg * std.math.pi / 180.0;
    const fit_h = (h * 0.5 + 1.5) / @tan(fov_rad * 0.5);
    const fit_w = (w * 0.5 + 1.5) / (@tan(fov_rad * 0.5) * aspect);
    const dist = @max(fit_h, fit_w) + w * 0.15;
    const tilt = tilt_deg * std.math.pi / 180.0;
    const eye = [3]f32{ cx, cy - @sin(tilt) * dist * 0.35, @cos(tilt) * dist };
    const center = [3]f32{ cx, cy, 0 };
    const view = lookAt(eye, center, .{ 0, 1, 0 });
    const proj = perspective(fov_y_deg, aspect, DEFAULT_NEAR, DEFAULT_FAR);
    return .{ .eye = eye, .center = center, .view = view, .proj = proj, .view_proj = mul(proj, view) };
}

pub fn defaultView(w_cells: u32, h_cells: u32, margin: f32, aspect: f32, tilt_deg: f32, fov_y_deg: f32) FitView {
    const wf: f32 = @floatFromInt(w_cells);
    const total_w: u32 = @intFromFloat(@ceil(wf + margin * 2.0));
    var fit = fitBoard(total_w, h_cells, aspect, tilt_deg, fov_y_deg);
    const shift = wf * 0.5 - (@as(f32, @floatFromInt(total_w))) * 0.5;
    fit.eye[0] += shift;
    fit.center[0] += shift;
    fit.view = lookAt(fit.eye, fit.center, .{ 0, 1, 0 });
    fit.view_proj = mul(fit.proj, fit.view);
    return fit;
}

pub fn yawPitchFor(eye: [3]f32, center: [3]f32) struct { yaw: f32, pitch: f32 } {
    const dx = center[0] - eye[0];
    const dy = center[1] - eye[1];
    const dz = center[2] - eye[2];
    const len = @sqrt(dx * dx + dy * dy + dz * dz);
    const pitch = std.math.asin(dy / len);
    const yaw = std.math.atan2(-dx / len, -dz / len);
    return .{ .yaw = yaw, .pitch = pitch };
}

test "fov70" {
    try std.testing.expectEqual(@as(f32, 70.0), DEFAULT_FOV_Y_DEG);
}

test "persp" {
    const m = perspective(70.0, 16.0 / 9.0, 0.1, 200.0);
    const f = 1.0 / @tan(70.0 * std.math.pi / 180.0 * 0.5);
    try std.testing.expectApproxEqAbs(f / (16.0 / 9.0), m[0], 1e-5);
    try std.testing.expectApproxEqAbs(-f, m[5], 1e-5);
}

test "depth" {
    const m = perspective(70.0, 16.0 / 9.0, 0.1, 200.0);
    const on_near = projectNdc(m, .{ 0, 0, -0.1 }) orelse return error.Clipped;
    try std.testing.expectApproxEqAbs(@as(f32, 0), on_near[2], 1e-4);
    const on_far = projectNdc(m, .{ 0, 0, -200 }) orelse return error.Clipped;
    try std.testing.expectApproxEqAbs(@as(f32, 1), on_far[2], 1e-3);
    const mid = projectNdc(m, .{ 0, 0, -20 }) orelse return error.Clipped;
    try std.testing.expect(mid[2] > 0 and mid[2] < 1);
    try std.testing.expect(projectNdc(m, .{ 0, 0, 1 }) == null);
}

test "view" {
    const v = defaultView(10, 20, 7.0, 16.0 / 9.0, 8.0, 70.0);
    const dx = 5 - v.eye[0];
    const dy = 10 - v.eye[1];
    const dz = 0 - v.eye[2];
    const fwd = [3]f32{ v.center[0] - v.eye[0], v.center[1] - v.eye[1], v.center[2] - v.eye[2] };
    const fl = @sqrt(fwd[0] * fwd[0] + fwd[1] * fwd[1] + fwd[2] * fwd[2]);
    const along = (dx * fwd[0] + dy * fwd[1] + dz * fwd[2]) / fl;
    try std.testing.expect(along > DEFAULT_NEAR and along < DEFAULT_FAR);
    const ndc = projectNdc(mul(v.proj, v.view), .{ 5, 10, 0 }) orelse return error.Clipped;
    try std.testing.expect(@abs(ndc[0]) < 1 and @abs(ndc[1]) < 1);
    try std.testing.expect(ndc[2] > 0 and ndc[2] < 1);
}

test "fit" {
    const v = fitBoard(10, 40, 16.0 / 9.0, 8.0, 70.0);
    try std.testing.expect(v.eye[2] > 0);
    for (v.view_proj) |x| try std.testing.expect(std.math.isFinite(x));
}

test "fit sizes" {
    const big = fitBoard(100, 100, 16.0 / 9.0, 8.0, 70.0);
    const tiny = fitBoard(4, 1, 16.0 / 9.0, 8.0, 70.0);
    try std.testing.expect(big.eye[2] > tiny.eye[2]);
}

test "center" {
    const v = defaultView(10, 20, 7.0, 16.0 / 9.0, 8.0, 70.0);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), v.center[0], 1e-4);
    try std.testing.expect(v.eye[2] > 0);
    for (v.view_proj) |x| try std.testing.expect(std.math.isFinite(x));
}

test "yawpitch" {
    const eye = [3]f32{ 5, 8, 30 };
    const center = [3]f32{ 5, 10, 0 };
    const yp = yawPitchFor(eye, center);
    const cp = @cos(yp.pitch);
    const dir = [3]f32{ -@sin(yp.yaw) * cp, @sin(yp.pitch), -@cos(yp.yaw) * cp };
    var want = [3]f32{ center[0] - eye[0], center[1] - eye[1], center[2] - eye[2] };
    const len = @sqrt(want[0] * want[0] + want[1] * want[1] + want[2] * want[2]);
    want = .{ want[0] / len, want[1] / len, want[2] / len };
    try std.testing.expectApproxEqAbs(want[0], dir[0], 1e-5);
    try std.testing.expectApproxEqAbs(want[1], dir[1], 1e-5);
    try std.testing.expectApproxEqAbs(want[2], dir[2], 1e-5);
}

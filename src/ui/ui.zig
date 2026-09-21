const std = @import("std");

pub const BackendKind = enum { stub, cimgui };

pub const Backend = struct {
    kind: BackendKind = .stub,
    frame_open: bool = false,
};

pub const Ui = struct {
    backend: Backend = .{},
    overlay_lines: usize = 0,

    pub fn beginFrame(self: *Ui) void {
        self.backend.frame_open = true;
        self.overlay_lines = 0;
    }

    pub fn endFrame(self: *Ui) void {
        self.backend.frame_open = false;
    }

    pub fn text(self: *Ui, comptime fmt: []const u8, args: anytype) void {
        if (self.backend.kind == .stub) {
            std.debug.print("[ui] " ++ fmt ++ "\n", args);
            self.overlay_lines += 1;
        }
    }

    pub fn button(self: *Ui, label: []const u8) bool {
        _ = self;
        _ = label;
        return false;
    }

    pub fn beginWindow(self: *Ui, name: []const u8) bool {
        _ = self;
        _ = name;
        return true;
    }

    pub fn endWindow(self: *Ui) void {
        _ = self;
    }
};

test "ui stub" {
    var ui = Ui{};
    ui.beginFrame();
    try std.testing.expect(ui.backend.frame_open);
    ui.text("score {d}", .{123});
    try std.testing.expect(ui.overlay_lines == 1);
    try std.testing.expect(!ui.button("restart"));
    ui.endFrame();
    try std.testing.expect(!ui.backend.frame_open);
}

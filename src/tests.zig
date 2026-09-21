const std = @import("std");

comptime {
    _ = @import("core/cell.zig");
    _ = @import("core/piece.zig");
    _ = @import("core/field.zig");
    _ = @import("core/srs.zig");
    _ = @import("core/bag.zig");
    _ = @import("core/config.zig");
    _ = @import("core/game.zig");
    _ = @import("render/camera.zig");
    _ = @import("render/freecam.zig");
    _ = @import("render/scene.zig");
    _ = @import("render/instance.zig");
    _ = @import("render/board_view.zig");
    _ = @import("ui/font.zig");
    _ = @import("net/proto.zig");
    _ = @import("ui/ui.zig");
    _ = @import("helper.zig");
}

test {
    std.testing.refAllDecls(@This());
}

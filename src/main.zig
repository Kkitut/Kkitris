const std = @import("std");
const logger = @import("logger.zig");
const app = @import("app.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    if (!logger.init(io, gpa)) return error.LoggerInitFailed;
    defer logger.deinit();

    try app.run(io, gpa);
}

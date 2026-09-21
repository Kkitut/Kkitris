const std = @import("std");

pub const PROTOCOL_VERSION: u32 = 1;

pub const MAX_PLAYERS = 8;

pub const ButtonsBits = packed struct(u16) {
    left: bool = false,
    right: bool = false,
    soft: bool = false,
    _pad: u13 = 0,
};

pub const InputFrame = packed struct(u64) {
    seq: u32,
    player: u8,
    action: u8,
    buttons: ButtonsBits,

    pub fn encode(self: InputFrame) [8]u8 {
        return @bitCast(self);
    }

    pub fn decode(bytes: [8]u8) InputFrame {
        return @bitCast(bytes);
    }
};

pub const StateHash = packed struct(u128) {
    tick: u64,
    hash: u64,

    pub fn encode(self: StateHash) [16]u8 {
        return @bitCast(self);
    }

    pub fn decode(bytes: [16]u8) StateHash {
        return @bitCast(bytes);
    }
};

pub const AttackMsg = packed struct(u64) {
    from_player: u8,
    to_player: u8,
    lines: u8,
    hole_seed: u16,
    tick: u16,
    _pad: u8 = 0,

    pub fn encode(self: AttackMsg) [8]u8 {
        return @bitCast(self);
    }

    pub fn decode(bytes: [8]u8) AttackMsg {
        return @bitCast(bytes);
    }
};

test "input" {
    const f = InputFrame{ .seq = 123, .player = 2, .action = 5, .buttons = .{ .left = true } };
    const back = InputFrame.decode(f.encode());
    try std.testing.expectEqual(f.seq, back.seq);
    try std.testing.expect(back.buttons.left);
}

test "statehash" {
    const h = StateHash{ .tick = 999, .hash = 0xdead_beef_cafe_1234 };
    const back = StateHash.decode(h.encode());
    try std.testing.expectEqual(h.hash, back.hash);
}

test "attack" {
    const a = AttackMsg{ .from_player = 0, .to_player = 1, .lines = 4, .hole_seed = 77, .tick = 1000 };
    const back = AttackMsg.decode(a.encode());
    try std.testing.expectEqual(a.lines, back.lines);
}

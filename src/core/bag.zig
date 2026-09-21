const std = @import("std");
const piece_mod = @import("piece.zig");
const PieceKind = piece_mod.PieceKind;

pub const Bag = struct {
    state: u64,
    queue: [7]PieceKind = undefined,
    index: usize = 7,
    bags_drawn: u64 = 0,

    pub fn init(seed: u64) Bag {
        return .{ .state = seed | 1 };
    }

    fn nextU64(self: *Bag) u64 {
        self.state +%= 0x9e3779b97f4a7c15;
        var z: u64 = self.state;
        z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
        z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
        return z ^ (z >> 31);
    }

    fn reshuffle(self: *Bag) void {
        for (0..7) |i| self.queue[i] = PieceKind.fromBagIndex(@intCast(i));
        var i: usize = 7;
        while (i > 1) {
            i -= 1;
            const j: usize = @as(usize, @intCast(self.nextU64() % (i + 1)));
            const tmp = self.queue[i];
            self.queue[i] = self.queue[j];
            self.queue[j] = tmp;
        }
        self.index = 0;
        self.bags_drawn += 1;
    }

    pub fn next(self: *Bag) PieceKind {
        if (self.index >= 7) self.reshuffle();
        const k = self.queue[self.index];
        self.index += 1;
        return k;
    }

    pub fn peek(self: *const Bag, n: usize) PieceKind {
        std.debug.assert(n < 14);
        if (self.index + n < 7) return self.queue[self.index + n];
        var tmp = self.*;
        var out: PieceKind = undefined;
        var i: usize = 0;
        while (i <= n) : (i += 1) out = tmp.next();
        return out;
    }
};

test "7bag" {
    var b = Bag.init(1234);
    var seen = [_]bool{false} ** 7;
    for (0..7) |_| {
        const k = b.next();
        const i = @intFromEnum(k);
        try std.testing.expect(!seen[i]);
        seen[i] = true;
    }
}

test "bag seed" {
    var a = Bag.init(99);
    var b = Bag.init(99);
    for (0..28) |_| try std.testing.expectEqual(a.next(), b.next());
}

test "bag peek" {
    var b = Bag.init(7);
    const p0 = b.peek(0);
    try std.testing.expectEqual(p0, b.next());
}

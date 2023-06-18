const std = @import("std");

pub fn Rect(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T,
        y: T,
        w: T,
        h: T,

        pub fn intersect(self: Self, other: Self) T {
            return @max(0, @min(self.x + self.w, other.x + other.w) - @max(self.x, other.x)) *
                @max(0, @min(self.y + self.h, other.y + other.h) - @max(self.y, other.y));
        }
    };
}

pub fn Vector(comptime T: type) type {
    return struct {
        x: T = 0,
        y: T = 0,
    };
}

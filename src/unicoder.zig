//! Zig module root file for unicoder
const std = @import("std");

test "module mentioned" {
    std.debug.print("hello from unicoder module\n", .{});
}

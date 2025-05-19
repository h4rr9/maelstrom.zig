pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .{};
    const gpa = gpa_state.allocator();
    defer {
        if (gpa_state.deinit() != .ok)
            _ = gpa_state.detectLeaks();
    }

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var node: Node = .init(stdin.any(), stdout.any(), gpa);
    defer node.deinit();

    try node.run();
}

const std = @import("std");
const Node = @import("Node.zig");

test {
    _ = @import("Node.zig");
    _ = @import("msg.zig");
}

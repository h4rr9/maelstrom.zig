pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .{};
    const gpa = gpa_state.allocator();
    defer {
        if (gpa_state.deinit() != .ok)
            _ = gpa_state.detectLeaks();
    }

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var node: Node(.{
        .echo = .{
            .handler = struct {
                fn handler(msg: *const MsgBody) !MsgBody {
                    return .{
                        .echo_ok = .{
                            .echo = msg.echo.echo,
                            .in_reply_to = msg.echo.msg_id,
                        },
                    };
                }
            }.handler,
        },
    }) = .init(stdin.any(), stdout.any(), gpa);
    defer node.deinit();

    try node.run();
}

const std = @import("std");
const lib = @import("lib");
const Node = lib.Node;
const MsgBody = lib.MsgBody;

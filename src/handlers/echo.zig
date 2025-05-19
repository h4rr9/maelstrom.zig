pub fn handler(node: *Node, msg: *const MsgBody, _: std.mem.Allocator) !MsgBody {
    return .{
        .echo_ok = .{
            .msg_id = node.nxt_msg_id,
            .echo = msg.echo.echo,
            .in_reply_to = msg.echo.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const MsgBody = @import("../msg.zig").MsgBody;
const std = @import("std");

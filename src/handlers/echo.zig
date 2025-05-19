pub fn handler(_: *Node, msg: *const MsgBody, _: std.mem.Allocator) !MsgBody {
    return .{
        .echo_ok = .{
            .echo = msg.echo.echo,
            .in_reply_to = msg.echo.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const MsgBody = @import("../msg.zig").MsgBody;
const std = @import("std");

pub fn handler(node: *Node, message: *const Message, _: std.mem.Allocator) !Body {
    const msg = message.body.echo;
    return .{
        .echo_ok = .{
            .msg_id = node.nxt_msg_id,
            .echo = msg.echo,
            .in_reply_to = msg.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const Message = @import("../msg.zig").Message;
const Body = @import("../msg.zig").Body;
const std = @import("std");

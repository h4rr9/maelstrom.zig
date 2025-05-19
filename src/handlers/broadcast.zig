pub fn handler(node: *Node, msg: *const MsgBody, _: std.mem.Allocator) !MsgBody {
    const msg_str = try std.json.stringifyAlloc(node.gpa, msg.broadcast.message, .{});

    // lock
    const entry = try node.messages.getOrPut(node.gpa, msg_str);

    if (!entry.found_existing)
        for (node.neighbours) |n|
            try node.send(n, .{
                .broadcast = .{
                    .msg_id = node.nxt_msg_id,
                    .message = msg.broadcast.message,
                },
            });

    return .{
        .broadcast_ok = .{
            .msg_id = node.nxt_msg_id,
            .in_reply_to = msg.broadcast.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const MsgBody = @import("../msg.zig").MsgBody;
const std = @import("std");

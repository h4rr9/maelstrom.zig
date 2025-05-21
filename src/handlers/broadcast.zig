pub fn handler(node: *Node, message: *const Message, _: std.mem.Allocator) !Body {
    const msg = message.body.broadcast;
    const msg_str = try std.json.stringifyAlloc(node.gpa, msg.message, .{});

    // lock
    const entry = try node.messages.getOrPut(node.gpa, msg_str);

    if (!entry.found_existing)
        for (node.neighbours) |n|
            if (!std.mem.eql(u8, n, message.src))
                try node.send(n, .{
                    .broadcast = .{
                        .msg_id = node.nxt_msg_id,
                        .message = msg.message,
                    },
                }, null);

    return .{
        .broadcast_ok = .{
            .msg_id = node.nxt_msg_id,
            .in_reply_to = msg.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const Message = @import("../msg.zig").Message;
const Body = @import("../msg.zig").Body;
const std = @import("std");

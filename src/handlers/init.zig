pub fn handler(node: *Node, message: *const Message, _: std.mem.Allocator) !Body {
    const msg = message.body.init;
    node.nxt_msg_id = 1;
    node.id = try node.gpa.dupe(u8, msg.node_id);
    node.node_ids = blk: {
        const node_ids = try node.gpa.alloc([]const u8, msg.node_ids.len);
        for (node_ids, msg.node_ids) |*node_id, nid|
            node_id.* = try node.gpa.dupe(u8, nid);
        break :blk node_ids;
    };

    return .{
        .init_ok = .{
            .msg_id = 0,
            .in_reply_to = msg.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const Message = @import("../msg.zig").Message;
const Body = @import("../msg.zig").Body;
const std = @import("std");

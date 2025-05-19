pub fn handler(node: *Node, msg: *const MsgBody, _: std.mem.Allocator) !MsgBody {
    node.nxt_msg_id = 1;
    node.id = try node.gpa.dupe(u8, msg.init.node_id);
    node.node_ids = blk: {
        const node_ids = try node.gpa.alloc([]const u8, msg.init.node_ids.len);
        for (node_ids, msg.init.node_ids) |*node_id, nid| {
            node_id.* = try node.gpa.dupe(u8, nid);
        }
        break :blk node_ids;
    };

    return .{
        .init_ok = .{
            .msg_id = 0,
            .in_reply_to = msg.init.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const MsgBody = @import("../msg.zig").MsgBody;
const std = @import("std");

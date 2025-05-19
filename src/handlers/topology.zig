pub fn handler(node: *Node, msg: *const MsgBody, _: std.mem.Allocator) !MsgBody {
    if (msg.topology.topology._topology.get(node.id)) |topo| {
        std.log.info("My neighbours are  {s}", .{std.json.fmt(topo, .{})});
        node.neighbours = try node.gpa.alloc([]const u8, topo.len);
        for (topo, node.neighbours) |t, *n|
            n.* = try node.gpa.dupe(u8, t);
    } else {
        std.log.err("topology not found for node {s}", .{node.id});
        return error.MissingTopology;
    }

    return .{
        .topology_ok = .{
            .msg_id = node.nxt_msg_id,
            .in_reply_to = msg.topology.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const MsgBody = @import("../msg.zig").MsgBody;
const std = @import("std");

pub fn handler(node: *Node, message: *const Message, _: std.mem.Allocator) !Body {
    const msg = message.body.topology;

    if (msg.topology._topology.get(node.id)) |topo| {
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
            .in_reply_to = msg.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const Message = @import("../msg.zig").Message;
const Body = @import("../msg.zig").Body;
const std = @import("std");

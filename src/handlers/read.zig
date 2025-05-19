pub fn handler(node: *Node, msg: *const MsgBody, arena: std.mem.Allocator) !MsgBody {
    // handler arena will take care of allocations

    var msgs: std.ArrayListUnmanaged(std.json.Value) = try .initCapacity(arena, node.messages.count());
    for (node.messages.keys()) |m| {
        const parsed = try std.json.parseFromSlice(std.json.Value, arena, m, .{});
        msgs.appendAssumeCapacity(parsed.value);
    }

    return .{
        .read_ok = .{
            .messages = msgs.items,
            .msg_id = node.nxt_msg_id,
            .in_reply_to = msg.read.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const MsgBody = @import("../msg.zig").MsgBody;
const std = @import("std");

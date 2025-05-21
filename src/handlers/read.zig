pub fn handler(node: *Node, message: *const Message, arena: std.mem.Allocator) !Body {
    const msg = message.body.read;
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
            .in_reply_to = msg.msg_id,
        },
    };
}

const Node = @import("../Node.zig");
const Message = @import("../msg.zig").Message;
const Body = @import("../msg.zig").Body;
const std = @import("std");

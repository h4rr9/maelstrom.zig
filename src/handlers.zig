const HandlerType = *const fn (node: *Node, message: *const Message, arena: std.mem.Allocator) anyerror!Body;

pub const Handler = struct {
    handlerFn: ?HandlerType,

    pub const none: @This() = .{ .handlerFn = null };
};

pub const HandlerImpls = std.enums.EnumFieldStruct(RequestType, Handler, .none);

pub const default_handler_impls: HandlerImpls = .{
    .init = .{ .handlerFn = @import("handlers/init.zig").handler },
    .echo = .{ .handlerFn = @import("handlers/echo.zig").handler },
    .topology = .{ .handlerFn = @import("handlers/topology.zig").handler },
    .broadcast = .{ .handlerFn = @import("handlers/broadcast.zig").handler },
    .read = .{ .handlerFn = @import("handlers/read.zig").handler },
    .generate = .{ .handlerFn = @import("handlers/generate.zig").handler },
};

pub const Handlers = struct {
    impls: HandlerImpls,

    pub fn handler(
        self: *const Handlers,
        node: *Node,
        message: *const Message,
        arena: std.mem.Allocator,
        comptime handler_tag: RequestType,
    ) !void {
        const handler_impl = @field(self.impls, @tagName(handler_tag));
        const msg = @field(message.body, @tagName(handler_tag));

        const response_body: Body = if (handler_impl.handlerFn) |hfn|
            @call(
                .auto,
                hfn,
                .{ node, message, arena },
            ) catch |err| switch (err) {
                else => .{
                    .@"error" = .{
                        .in_reply_to = msg.msg_id,
                        .code = .crash,
                        .text = @errorName(err),
                    },
                },
            }
        else
            .{
                .@"error" = .{
                    .in_reply_to = msg.msg_id,
                    .code = .not_supported,
                    .text = @tagName(handler_tag) ++ " is not supported",
                },
            };

        try node.send(message.src, response_body, handler_tag);
        _ = node.arena_state.reset(.{ .retain_with_limit = 4 * 1024 * 1024 });
    }
};

pub const default_handlers: Handlers = .{ .impls = default_handler_impls };

const Message = @import("msg.zig").Message;
const Body = @import("msg.zig").Body;
const RequestType = @import("msg.zig").RequestType;
const Node = @import("Node.zig");
const std = @import("std");

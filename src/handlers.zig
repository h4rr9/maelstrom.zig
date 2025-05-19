const HandlerType = *const fn (node: *Node, msg: *const MsgBody, arena: std.mem.Allocator) anyerror!MsgBody;

pub const Handler = struct {
    handler: ?HandlerType,
    pub const none: @This() = .{ .handler = null };
};

pub const Handlers = std.enums.EnumFieldStruct(RequestType, Handler, .none);
pub const HandlerArray = [std.enums.directEnumArrayLen(RequestType, 0)]Handler;

pub const default_handlers: Handlers = .{
    .init = .{ .handler = @import("handlers/init.zig").handler },
    .echo = .{ .handler = @import("handlers/echo.zig").handler },
    .topology = .{ .handler = @import("handlers/topology.zig").handler },
    .broadcast = .{ .handler = @import("handlers/broadcast.zig").handler },
    .read = .{ .handler = @import("handlers/read.zig").handler },
};

pub fn customhandlers(h: Handlers) HandlerArray {
    return std.enums.directEnumArrayDefault(RequestType, Handler, .none, 0, h);
}

pub const handlers = customhandlers(default_handlers);

const MsgBody = @import("msg.zig").MsgBody;
const RequestType = @import("msg.zig").RequestType;
const Node = @import("Node.zig");
const std = @import("std");

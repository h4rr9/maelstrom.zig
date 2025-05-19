const Node = @This();

nxt_msg_id: u32 = 0,
id: []const u8,
node_ids: [][]const u8,

handlers: HandlerArray,
// comptime callbacks: std.enums.directEnumArray(RequestType, ?Handler, 0, .{}),

in: std.io.AnyReader,
out: std.io.AnyWriter,
gpa: std.mem.Allocator,
arena_state: std.heap.ArenaAllocator,

line: std.ArrayListUnmanaged(u8) = .empty,

pub fn init(
    in: std.io.AnyReader,
    out: std.io.AnyWriter,
    gpa: std.mem.Allocator,
) @This() {
    return .initWithHandlers(in, out, gpa, default_handlers);
}

pub fn initWithHandlers(
    in: std.io.AnyReader,
    out: std.io.AnyWriter,
    gpa: std.mem.Allocator,
    handlers: Handlers,
) @This() {
    var new_handlers = handlers;
    if (handlers.init.handler == null) {
        new_handlers.init = default_handlers.init;
    }

    return .{
        .in = in,
        .out = out,
        .gpa = gpa,
        .arena_state = std.heap.ArenaAllocator.init(gpa),
        .id = undefined,
        .node_ids = &.{},
        .handlers = customHandlers(new_handlers),
    };
}

pub fn deinit(node: *Node) void {
    node.gpa.free(node.id);
    node.line.deinit(node.gpa);
    node.arena_state.deinit();
    for (node.node_ids) |node_id| node.gpa.free(node_id);
    node.gpa.free(node.node_ids);
}

fn recv(node: *Node) !?Message {
    var line = node.line.toManaged(node.gpa);
    defer node.line = .initBuffer(line.allocatedSlice());
    errdefer line.deinit();

    node.in.streamUntilDelimiter(line.writer(), '\n', null) catch |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    };

    // NOTE: parsed is passed in arena, no need to deinit
    // arena will be reset when next message is read
    const parsed = try std.json.parseFromSlice(Message, node.arena_state.allocator(), line.items, .{ .ignore_unknown_fields = true });
    return parsed.value;
}

fn send(node: *Node, dest: []const u8, resp_body: MsgBody) !void {
    node.nxt_msg_id += 1;
    const message: Message = .{
        .src = node.id,
        .dest = dest,
        .body = resp_body,
    };
    try std.json.stringify(message, .{ .emit_null_optional_fields = false }, node.out);
    try node.out.writeByte('\n');
    _ = node.arena_state.reset(.{ .retain_with_limit = 4 * 1024 * 1024 });
}

pub fn run(node: *Node) !void {
    errdefer _ = node.arena_state.reset(.free_all);
    var message = try node.recv() orelse return;

    sw: switch (message.body) {
        inline else => |msg, tag| {
            const resp_body: MsgBody = if (node.handlers[@as(usize, @intFromEnum(tag.scoped(.request).?))].handler) |handler|
                @call(
                    .auto,
                    handler,
                    .{ node, &message.body, node.arena_state.allocator() },
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
                        .text = @tagName(tag) ++ " is not supported",
                    },
                };

            // if .init errors out node.id is undefined
            // set it to duped string so json.stringify
            // and deinit do not error out.
            if ((comptime tag == .init) and resp_body == .@"error")
                node.id = try node.gpa.dupe(u8, "<undefined>");

            try node.send(message.src, resp_body);
            message = try node.recv() orelse return;
            continue :sw message.body;
        },
        .init_ok, .echo_ok, .topology_ok, .broadcast_ok, .read_ok, .@"error" => {
            message = try node.recv() orelse return;
            continue :sw message.body;
        },
    }
}

const INIT_JSON_STR =
    \\{"src":"x","dest":"y","body":{"type":"init","msg_id":1,"node_id":"n3","node_ids":["n1","n2","n3"]}}
    \\
;
const ECHO_JSON_STR =
    \\{"src":"x","dest":"y","body":{"type":"echo","msg_id":42,"echo":{"object":{"one":1,"two":2},"string":"This is a string","array":["Another string",1,3.5],"int":10,"float":3.5}}}
    \\
;

const DummyCtx = struct { idx: usize = 0, data: []const u8 };
const DummyReader = std.io.GenericReader(*DummyCtx, error{}, struct {
    fn read(ctx: *DummyCtx, buffer: []u8) !usize {
        if (ctx.idx >= ctx.data.len) return 0;
        const len = @min(buffer.len, ctx.data.len - ctx.idx);
        @memcpy(buffer[0..len], ctx.data[ctx.idx..][0..len]);
        ctx.idx += len;
        return len;
    }
}.read);

test "initMessage" {
    var buffer: std.ArrayList(u8) = .init(std.testing.allocator);
    defer buffer.deinit();

    var ctx = DummyCtx{ .data = INIT_JSON_STR };
    const out = buffer.writer();
    const in: DummyReader = .{ .context = &ctx };
    var node: Node = .initWithHandlers(in.any(), out.any(), std.testing.allocator, .{});
    try node.run();
    defer node.deinit();

    const parsed = try std.json.parseFromSlice(Message, std.testing.allocator, buffer.items, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.body == .init_ok);
    try std.testing.expectEqualStrings("n3", node.id);
}

test "run" {
    var buffer: std.ArrayList(u8) = .init(std.testing.allocator);
    defer buffer.deinit();

    var ctx = DummyCtx{ .data = INIT_JSON_STR ++ ECHO_JSON_STR };
    const out = buffer.writer();
    const in: DummyReader = .{ .context = &ctx };
    var node: Node = .initWithHandlers(in.any(), out.any(), std.testing.allocator, .{
        .echo = struct {
            fn _handler(_: *Node, msg: *const MsgBody, arena: std.mem.Allocator) !MsgBody {
                // alloc for arena leak detection
                _ = try arena.alloc(u8, 1);
                return .{
                    .echo_ok = .{
                        .echo = msg.echo.echo,
                        .in_reply_to = msg.echo.msg_id,
                    },
                };
            }

            pub fn handler() Handler {
                return .{ .handler = _handler };
            }
        }.handler(),
    });
    defer node.deinit();

    try node.run();

    var iter = std.mem.splitScalar(u8, buffer.items, '\n');
    _ = iter.next();

    const parsed = try std.json.parseFromSlice(Message, std.testing.allocator, iter.next().?, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.body == .echo_ok);
}

test "not_supported" {
    var buffer: std.ArrayList(u8) = .init(std.testing.allocator);
    defer buffer.deinit();

    var ctx = DummyCtx{ .data = INIT_JSON_STR ++ ECHO_JSON_STR };
    const out = buffer.writer();
    const in: DummyReader = .{ .context = &ctx };
    var node: Node = .initWithHandlers(in.any(), out.any(), std.testing.allocator, .{});
    defer node.deinit();

    try node.run();

    var iter = std.mem.splitScalar(u8, buffer.items, '\n');
    _ = iter.next();

    const parsed = try std.json.parseFromSlice(Message, std.testing.allocator, iter.next().?, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.body == .@"error");
    try std.testing.expect(parsed.value.body.@"error".code == .not_supported);
}

test "crashed" {
    var buffer: std.ArrayList(u8) = .init(std.testing.allocator);
    defer buffer.deinit();

    var ctx = DummyCtx{ .data = INIT_JSON_STR ++ ECHO_JSON_STR };
    const out = buffer.writer();
    const in: DummyReader = .{ .context = &ctx };
    var node: Node = .initWithHandlers(in.any(), out.any(), std.testing.allocator, .{
        .echo = struct {
            fn _handler(_: *Node, _: *const MsgBody, _: std.mem.Allocator) !MsgBody {
                return error.NotImplemented;
            }
            pub fn handler() Handler {
                return .{ .handler = _handler };
            }
        }.handler(),
    });
    defer node.deinit();

    try node.run();

    var iter = std.mem.splitScalar(u8, buffer.items, '\n');
    _ = iter.next();

    const parsed = try std.json.parseFromSlice(Message, std.testing.allocator, iter.next().?, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.body == .@"error");
    try std.testing.expect(parsed.value.body.@"error".code == .crash);
}

const std = @import("std");
const builtin = @import("builtin");
const Message = @import("msg.zig").Message;
const MsgBody = @import("msg.zig").MsgBody;
const RequestType = @import("msg.zig").RequestType;
const ScopedMsgType = @import("msg.zig").ScopedMsgType;
const customHandlers = @import("handlers.zig").customhandlers;
const Handlers = @import("handlers.zig").Handlers;
const Handler = @import("handlers.zig").Handler;
const HandlerArray = @import("handlers.zig").HandlerArray;
const handlers_array = @import("handlers.zig").handlers;
const default_handlers = @import("handlers.zig").default_handlers;

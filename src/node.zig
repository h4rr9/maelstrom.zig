pub const Handler = struct {
    const none: Handler = .{ .handler = null };

    handler: ?*const fn (msg: *const MsgBody) anyerror!MsgBody,
};

const RequestType = ScopedMsgType(.request);

pub fn Node(comptime handler_values: std.enums.EnumFieldStruct(RequestType, Handler, .none)) type {
    const handlers = std.enums.directEnumArrayDefault(RequestType, Handler, .none, 0, handler_values);

    return struct {
        const Self = @This();
        const Len = std.enums.directEnumArrayLen(RequestType, 0);

        nxt_msg_id: u32 = 0,
        id: []const u8,
        node_ids: [][]const u8,

        comptime handlers: @TypeOf(handlers) = handlers,
        // comptime callbacks: std.enums.directEnumArray(RequestType, ?Handler, 0, .{}),

        in: std.io.AnyReader,
        out: std.io.AnyWriter,
        gpa: std.mem.Allocator,

        line: std.ArrayListUnmanaged(u8) = .empty,

        fn handleInitMessage(node: *Self) !void {
            var line = node.line.toManaged(node.gpa);
            errdefer line.deinit();

            try node.in.streamUntilDelimiter(line.writer(), '\n', null);
            defer line.clearRetainingCapacity();

            const parsed = try std.json.parseFromSlice(Message, node.gpa, line.items, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();

            std.debug.assert(parsed.value.body == .init);

            const response: Message = .{
                .src = parsed.value.body.init.node_id,
                .dest = parsed.value.src,
                .body = .{
                    .init_ok = .{
                        .msg_id = 0,
                        .in_reply_to = parsed.value.body.init.msg_id,
                    },
                },
            };

            try std.json.stringify(response, .{ .emit_null_optional_fields = false }, node.out);
            try node.out.writeByte('\n');

            node.* = .{
                .nxt_msg_id = 1,
                .id = try node.gpa.dupe(u8, parsed.value.body.init.node_id),
                .node_ids = blk: {
                    const node_ids = try node.gpa.alloc([]const u8, parsed.value.body.init.node_ids.len);
                    for (node_ids, parsed.value.body.init.node_ids) |*node_id, nid| {
                        node_id.* = try node.gpa.dupe(u8, nid);
                    }
                    break :blk node_ids;
                },
                .in = node.in,
                .out = node.out,
                .gpa = node.gpa,
                .line = .initBuffer(line.allocatedSlice()),
            };
        }

        pub fn init(
            in: std.io.AnyReader,
            out: std.io.AnyWriter,
            gpa: std.mem.Allocator,
        ) @This() {
            return .{
                .in = in,
                .out = out,
                .gpa = gpa,
                .id = undefined,
                .node_ids = undefined,
            };
        }

        pub fn deinit(node: *Self) void {
            node.line.deinit(node.gpa);
            node.gpa.free(node.id);
            for (node.node_ids) |node_id| node.gpa.free(node_id);
            node.gpa.free(node.node_ids);
        }

        pub fn run(node: *Self) !void {
            try node.handleInitMessage();

            var line = node.line.toManaged(node.gpa);
            defer node.line = .initBuffer(line.allocatedSlice());

            loop: while (true) {
                node.in.streamUntilDelimiter(line.writer(), '\n', null) catch |err| switch (err) {
                    error.EndOfStream => return {},
                    else => return err,
                };

                defer line.clearRetainingCapacity();

                const parsed = try std.json.parseFromSlice(Message, node.gpa, line.items, .{ .ignore_unknown_fields = true });
                defer parsed.deinit();

                const response_body: MsgBody = switch (parsed.value.body) {
                    .init_ok, .echo_ok, .@"error" => continue :loop,
                    inline else => |body, tag| if (comptime node.handlers[@as(usize, @intFromEnum(tag.scoped(.request).?))].handler) |handler|
                        @call(
                            .always_inline,
                            handler,
                            .{&parsed.value.body},
                        ) catch |err| switch (err) {
                            else => .{
                                .@"error" = .{
                                    .in_reply_to = body.msg_id,
                                    .code = .crash,
                                    .text = @errorName(err),
                                },
                            },
                        }
                    else
                        .{ .@"error" = .{
                            .in_reply_to = body.msg_id,
                            .code = .not_supported,
                            .text = @tagName(tag) ++ " is not supported",
                        } },
                };
                node.nxt_msg_id += 1;

                const message: Message = .{
                    .src = parsed.value.dest,
                    .dest = parsed.value.src,
                    .body = response_body,
                };
                try std.json.stringify(message, .{ .emit_null_optional_fields = false }, node.out);
                try node.out.writeByte('\n');
            }
        }
    };
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
    var node: Node(.{}) = .init(in.any(), out.any(), std.testing.allocator);
    try node.handleInitMessage();
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
    var node: Node(.{
        .echo = struct {
            fn _handler(msg: *const MsgBody) !MsgBody {
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
    }) = .init(
        in.any(),
        out.any(),
        std.testing.allocator,
    );
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
    var node: Node(.{}) = .init(
        in.any(),
        out.any(),
        std.testing.allocator,
    );
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
    var node: Node(.{
        .echo = struct {
            fn _handler(_: *const MsgBody) !MsgBody {
                return error.NotImplemented;
            }
            pub fn handler() Handler {
                return .{ .handler = _handler };
            }
        }.handler(),
    }) = .init(
        in.any(),
        out.any(),
        std.testing.allocator,
    );
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
const Message = @import("msg.zig").Message;
const MsgBody = @import("msg.zig").MsgBody;
const ScopedMsgType = @import("msg.zig").ScopedMsgType;

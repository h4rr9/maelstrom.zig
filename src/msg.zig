const std = @import("std");

pub const ErrorType = enum(u16) {
    timeout = 0,
    node_not_found = 1,
    not_supported = 10,
    temporarily_unavailable = 11,
    malformed_request = 12,
    crash = 13,
    abort = 14,
    key_does_not_exist = 20,
    key_already_exists = 21,
    precondition_failed = 22,
    txn_conflict = 30,
};

const EventType = enum { request, response };

pub fn ScopedMsgType(comptime e: EventType) type {
    const all_fields = @typeInfo(MsgType).@"enum".fields;

    // Find all fields that are scoped to s
    var i: usize = 0;
    var fields: [all_fields.len]std.builtin.Type.EnumField = undefined;
    inline for (all_fields) |field| {
        const message_type: MsgType = @enumFromInt(field.value);
        if (message_type.event() == e) {
            fields[i] = field;
            i += 1;
        }
    }

    // Build our union
    return @Type(.{ .@"enum" = .{
        .tag_type = @typeInfo(MsgType).@"enum".tag_type,
        .fields = fields[0..i],
        .decls = &.{},
        .is_exhaustive = @typeInfo(MsgType).@"enum".is_exhaustive,
    } });
}

pub const RequestType = ScopedMsgType(.request);

pub const MsgType = enum(u8) {
    // NOTE: do not change order of fields, add new fields
    // to the end of reqeusts and responses
    init,
    echo,
    topology,
    broadcast,
    read,
    generate,

    // responses
    init_ok,
    echo_ok,
    topology_ok,
    broadcast_ok,
    read_ok,
    generate_ok,

    // erorr
    @"error",

    pub fn str(self: MsgType) []const u8 {
        return switch (self) {
            inline else => |t| @tagName(t),
        };
    }

    pub fn event(self: MsgType) EventType {
        return switch (self) {
            .init, .echo, .topology, .broadcast, .read, .generate => .request,
            .init_ok, .echo_ok, .topology_ok, .broadcast_ok, .read_ok, .generate_ok, .@"error" => .response,
        };
    }

    pub fn scoped(self: MsgType, comptime e: EventType) ?ScopedMsgType(e) {
        switch (self) {
            inline else => |tag| {
                if (comptime tag.event() != e) return null;
                return @enumFromInt(@intFromEnum(tag));
            },
        }
    }
};

pub const Body = union(MsgType) {
    init: struct {
        msg_id: u32,
        node_id: []const u8,
        node_ids: [][]const u8,
    },
    echo: struct {
        msg_id: u32,
        echo: std.json.Value,
    },
    topology: struct {
        msg_id: u32,
        topology: struct {
            _topology: std.StringArrayHashMap([][]const u8),
            const Self = @This();

            pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, _: std.json.ParseOptions) !Self {
                var map: std.StringArrayHashMap([][]const u8) = .init(allocator);
                errdefer map.deinit();

                if (source != .object)
                    return error.UnexpectedToken;

                var iter = source.object.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.* != .array)
                        return error.UnexpectedToken;
                    const arr: std.json.Array = entry.value_ptr.array;

                    const new_arr = try allocator.alloc([]const u8, arr.items.len);

                    for (arr.items, new_arr) |x, *y| {
                        if (x != .string)
                            return error.UnexpectedToken;
                        y.* = try allocator.dupe(u8, x.string);
                    }

                    try map.put(entry.key_ptr.*, new_arr);
                }

                return .{ ._topology = map };
            }

            pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
                const parsed = try std.json.Value.jsonParse(allocator, source, options);
                return Self.jsonParseFromValue(allocator, parsed, options);
            }

            pub fn jsonStringify(self: @This(), jws: anytype) !void {
                try jws.beginObject();
                var iter = self._topology.iterator();
                while (iter.next()) |entry| {
                    try jws.objectField(entry.key_ptr.*);
                    try jws.write(entry.value_ptr);
                }
                try jws.endObject();
            }
        },
    },
    broadcast: struct {
        msg_id: u32,
        message: std.json.Value,
    },
    read: struct {
        msg_id: u32,
    },
    generate: struct { msg_id: u32 },

    init_ok: struct {
        msg_id: ?u32 = null,
        in_reply_to: u32,
    },
    echo_ok: struct {
        msg_id: ?u32 = null,
        echo: std.json.Value,
        in_reply_to: u32,
    },
    topology_ok: struct {
        msg_id: ?u32,
        in_reply_to: u32,
    },
    broadcast_ok: struct {
        msg_id: ?u32,
        in_reply_to: u32,
    },
    read_ok: struct {
        messages: []std.json.Value,
        msg_id: ?u32,
        in_reply_to: u32,
    },
    generate_ok: struct {
        id: std.json.Value,
        msg_id: ?u32,
        in_reply_to: u32,
    },
    @"error": struct {
        in_reply_to: u32,
        code: ErrorType,
        text: []const u8,
    },

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("type");
        switch (self) {
            inline else => |payload, tag| {
                try jws.write(tag.str());
                inline for (std.meta.fields(@FieldType(@This(), tag.str()))) |Field| {
                    if (Field.type == void) continue;

                    var emit_field = true;

                    if (@typeInfo(Field.type) == .optional) {
                        if (jws.options.emit_null_optional_fields == false) {
                            if (@field(payload, Field.name) == null) {
                                emit_field = false;
                            }
                        }
                    }

                    if (emit_field) {
                        try jws.objectField(Field.name);
                        try jws.write(@field(payload, Field.name));
                    }
                }
            },
        }
        try jws.endObject();
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
        var map = switch (source) {
            .object => |obj| obj,
            else => return error.UnexpectedToken,
        };

        map.lockPointers();
        defer map.unlockPointers();

        const type_str = map.get("type") orelse return error.MissingField;
        const type_val = try std.json.innerParseFromValue(MsgType, allocator, type_str, options);

        return switch (type_val) {
            inline else => |t| body: {
                const B = @FieldType(@This(), t.str());
                var r: B = undefined;

                inline for (std.meta.fields(B)) |Field| {
                    if (Field.type == void) continue;

                    const val = map.get(Field.name);

                    @field(r, Field.name) = blk: {
                        if (@typeInfo(Field.type) == .optional and val == null)
                            break :blk null
                        else if (val) |v| {
                            break :blk try std.json.innerParseFromValue(Field.type, allocator, v, options);
                        } else return error.MissingField;
                    };
                }

                break :body @unionInit(@This(), t.str(), r);
            },
        };
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const parsed = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, parsed, options);
    }
};

pub const Message = struct {
    src: []const u8,
    dest: []const u8,
    body: Body,
};

test "init" {
    const init_json_str =
        \\{
        \\  "src": "x",
        \\  "dest": "y",
        \\  "body": {
        \\    "type": "init",
        \\    "msg_id": 1,
        \\    "node_id": "n3",
        \\    "node_ids": [
        \\      "n1",
        \\      "n2",
        \\      "n3"
        \\    ]
        \\  }
        \\}
    ;

    const expected_init_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, init_json_str, .{});
    defer expected_init_json.deinit();

    var parsed = try std.json.parseFromValue(Message, std.testing.allocator, expected_init_json.value, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.body == .init);
    try std.testing.expectEqualStrings("x", parsed.value.src);
    try std.testing.expectEqualStrings("y", parsed.value.dest);
    try std.testing.expectEqual(1, parsed.value.body.init.msg_id);
    try std.testing.expectEqualStrings("n3", parsed.value.body.init.node_id);
    // does not work for some reason
    // try std.testing.expectEqualSlices([]const u8, parsed.value.body.init.node_ids, &.{ "n1", "n2", "n3" });
    try std.testing.expectEqual(3, parsed.value.body.init.node_ids.len);
    try std.testing.expectEqualStrings(parsed.value.body.init.node_ids[0], "n1");
    try std.testing.expectEqualStrings(parsed.value.body.init.node_ids[1], "n2");
    try std.testing.expectEqualStrings(parsed.value.body.init.node_ids[2], "n3");

    var buffer: std.ArrayList(u8) = try .initCapacity(std.testing.allocator, init_json_str.len);
    defer buffer.deinit();

    try std.json.stringify(parsed.value, .{ .emit_null_optional_fields = false, .whitespace = .indent_2 }, buffer.writer());
    try std.testing.expectEqualStrings(init_json_str, buffer.items);
}

test "init_ok" {
    const init_ok_json_str =
        \\{
        \\  "src": "x",
        \\  "dest": "y",
        \\  "body": {
        \\    "type": "init_ok",
        \\    "in_reply_to": 1
        \\  }
        \\}
    ;

    const expected_init_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, init_ok_json_str, .{});
    defer expected_init_json.deinit();

    var parsed = try std.json.parseFromValue(Message, std.testing.allocator, expected_init_json.value, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.body == .init_ok);
    try std.testing.expectEqual(1, parsed.value.body.init_ok.in_reply_to);
    try std.testing.expectEqual(null, parsed.value.body.init_ok.msg_id);

    var buffer: std.ArrayList(u8) = try .initCapacity(std.testing.allocator, init_ok_json_str.len);
    defer buffer.deinit();

    try std.json.stringify(parsed.value, .{ .emit_null_optional_fields = false, .whitespace = .indent_2 }, buffer.writer());
    try std.testing.expectEqualStrings(init_ok_json_str, buffer.items);
}

test "echo" {
    const echo_json_str =
        \\{
        \\  "src": "x",
        \\  "dest": "y",
        \\  "body": {
        \\    "type": "echo",
        \\    "msg_id": 42,
        \\    "echo": {
        \\      "object": {
        \\        "one": 1,
        \\        "two": 2e0
        \\      },
        \\      "string": "This is a string",
        \\      "array": [
        \\        "Another string",
        \\        1,
        \\        3.5e0
        \\      ],
        \\      "int": 10,
        \\      "float": 3.5e0
        \\    }
        \\  }
        \\}
    ;

    const expected_init_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, echo_json_str, .{});
    defer expected_init_json.deinit();

    var parsed = try std.json.parseFromValue(Message, std.testing.allocator, expected_init_json.value, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.body == .echo);
    try std.testing.expect(parsed.value.body.echo.msg_id == 42);

    var buffer: std.ArrayList(u8) = try .initCapacity(std.testing.allocator, echo_json_str.len);
    defer buffer.deinit();

    try std.json.stringify(parsed.value, .{ .emit_null_optional_fields = false, .whitespace = .indent_2 }, buffer.writer());
    try std.testing.expectEqualStrings(echo_json_str, buffer.items);
}

test "echo_ok" {
    const echo_json_str =
        \\{
        \\  "src": "x",
        \\  "dest": "y",
        \\  "body": {
        \\    "type": "echo_ok",
        \\    "msg_id": 42,
        \\    "echo": {
        \\      "object": {
        \\        "one": 1,
        \\        "two": 2e0
        \\      },
        \\      "string": "This is a string",
        \\      "array": [
        \\        "Another string",
        \\        1,
        \\        3.5e0
        \\      ],
        \\      "int": 10,
        \\      "float": 3.5e0
        \\    },
        \\    "in_reply_to": 17
        \\  }
        \\}
    ;

    const expected_init_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, echo_json_str, .{});
    defer expected_init_json.deinit();

    var parsed = try std.json.parseFromValue(Message, std.testing.allocator, expected_init_json.value, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.body == .echo_ok);
    try std.testing.expectEqual(42, parsed.value.body.echo_ok.msg_id);
    try std.testing.expectEqual(17, parsed.value.body.echo_ok.in_reply_to);

    var buffer: std.ArrayList(u8) = try .initCapacity(std.testing.allocator, echo_json_str.len);
    defer buffer.deinit();

    try std.json.stringify(parsed.value, .{ .emit_null_optional_fields = false, .whitespace = .indent_2 }, buffer.writer());
    try std.testing.expectEqualStrings(echo_json_str, buffer.items);
}

test "broadcast" {
    const broadcast_json_str =
        \\{
        \\  "src": "x",
        \\  "dest": "y",
        \\  "body": {
        \\    "type": "topology",
        \\    "msg_id": 123,
        \\    "topology": {
        \\      "nodeA": [
        \\        "nodeB",
        \\        "nodeC"
        \\      ],
        \\      "nodeB": [
        \\        "nodeD"
        \\      ],
        \\      "nodeC": [
        \\        "nodeD",
        \\        "nodeE"
        \\      ]
        \\    }
        \\  }
        \\}
    ;

    const expected_init_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, broadcast_json_str, .{});
    defer expected_init_json.deinit();

    var parsed = try std.json.parseFromValue(Message, std.testing.allocator, expected_init_json.value, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.body == .topology);
    try std.testing.expect(parsed.value.body.topology.msg_id == 123);

    try std.testing.expectEqual(3, parsed.value.body.topology.topology._topology.count());

    var buffer: std.ArrayList(u8) = try .initCapacity(std.testing.allocator, broadcast_json_str.len);
    defer buffer.deinit();

    try std.json.stringify(parsed.value, .{ .emit_null_optional_fields = false, .whitespace = .indent_2 }, buffer.writer());
    try std.testing.expectEqualStrings(broadcast_json_str, buffer.items);
}

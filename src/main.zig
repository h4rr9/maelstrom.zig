pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .{};
    const gpa = gpa_state.allocator();
    defer {
        if (gpa_state.deinit() != .ok)
            _ = gpa_state.detectLeaks();
    }

    const stdout_file = std.io.getStdOut().writer();
    // const stderr_file = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const stdin = std.io.getStdIn().reader();

    var line: std.ArrayList(u8) = .init(gpa);
    defer line.deinit();

    var msg_id: u32 = 1;

    const node_id: []const u8 = blk: {
        try stdin.streamUntilDelimiter(line.writer(), '\n', null);
        defer line.clearRetainingCapacity();

        const parsed = try std.json.parseFromSlice(Message, gpa, line.items, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        std.debug.assert(parsed.value.body == .init);

        const response: Message = .{
            .src = parsed.value.body.init.node_id,
            .dest = parsed.value.src,
            .body = .{
                .init_ok = .{
                    .msg_id = msg_id,
                    .in_reply_to = parsed.value.body.init.msg_id,
                },
            },
        };
        msg_id += 1;

        try std.json.stringify(response, .{ .emit_null_optional_fields = false }, stdout);
        try stdout.writeByte('\n');
        try bw.flush();

        break :blk try gpa.dupe(u8, parsed.value.body.init.node_id);
    };
    defer gpa.free(node_id);

    while (true) {
        stdin.streamUntilDelimiter(line.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => std.process.cleanExit(),
            else => return err,
        };
        defer line.clearRetainingCapacity();

        const parsed = try std.json.parseFromSlice(Message, gpa, line.items, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        std.debug.assert(parsed.value.body == .echo);

        const response: Message = .{
            .src = node_id,
            .dest = parsed.value.src,
            .body = .{
                .echo_ok = .{
                    .msg_id = msg_id,
                    .in_reply_to = parsed.value.body.echo.msg_id,
                    .echo = parsed.value.body.echo.echo,
                },
            },
        };
        msg_id += 1;

        try std.json.stringify(response, .{ .emit_null_optional_fields = false }, stdout);
        try stdout.writeByte('\n');
        try bw.flush();
    }
}

const std = @import("std");
const lib = @import("maelstrom_lib");
const Message = lib.Message;

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .{};
    const gpa = gpa_state.allocator();
    defer {
        if (gpa_state.deinit() != .ok)
            _ = gpa_state.detectLeaks();
    }

    const stdout_file = std.io.getStdOut().writer();
    const stdin_file = std.io.getStdIn().reader();

    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const stdin = stdin_file.any();

    var reader = std.json.reader(gpa, stdin);
    defer reader.deinit();

    const parsed = try std.json.parseFromTokenSource(lib.Message, gpa, &reader, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const response: lib.Message = .{
        .src = parsed.value.body.node_id.?,
        .dest = parsed.value.src,
        .body = .{
            .type = .init_ok,
            .msg_id = 1,
            .in_reply_to = parsed.value.body.msg_id,
        },
    };

    try std.json.stringify(response, .{ .emit_null_optional_fields = false }, stdout);

    std.log.info("got {any}", .{parsed.value});

    try bw.flush(); // Don't forget to flush!
}

const std = @import("std");
const lib = @import("maelstrom_lib");

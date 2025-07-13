const std = @import("std");
const jsonValidator = @import("json_reader/validate_json.zig");

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    try stdout.print("Hi there!", .{});

    const err = jsonValidator.JsonErrorData{ .character_at_offset = 'd', .offset = 10, .expected_characters = undefined };
    try jsonValidator.outputJsonError(err);
}

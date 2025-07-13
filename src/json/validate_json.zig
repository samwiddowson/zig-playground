const std = @import("std");

const debugPrint = std.debug.print;
const stdout = std.io.getStdOut().writer();

pub const JsonError = error{ UnmatchedClosingBrace, UnmatchedOpeningBrace, UnexpectedChar };
pub const JsonErrorData = struct { offset: usize, character_at_offset: u8, expected_characters: [2]u8 };

const JsonElement = enum { Key, Value };

fn isWhitespace(c: u8) bool {
    if (c == ' ' or c == '\n' or c == '\r') {
        return true;
    }
    return false;
}

fn isExpectedChar(char: u8, expected: [2]u8) bool {
    if (expected[0] == char or expected[1] == char) {
        return true;
    }
    return false;
}

/// Some basic Json validation checking
/// This will probably be replaced with the load object function
pub fn validateJson(
    buf: [*:0]const u8,
    error_data: *?JsonErrorData,
) JsonError!bool {
    var brace_depth: u16 = 0;
    var within_string: bool = false;
    var expected_chars: [2]u8 = undefined;
    expected_chars[0] = '{';
    expected_chars[1] = '{';
    var json_element: JsonElement = undefined;

    var i: usize = 0;

    while (buf[i] != 0) : (i += 1) {
        const char = buf[i];
        if (isWhitespace(char)) {
            continue;
        }

        // debugPrint("{c}", .{char});

        if (within_string) {
            if (char == '"') {
                within_string = false;
                if (json_element == .Key) {
                    expected_chars[0] = ':';
                    expected_chars[1] = ':';
                    continue;
                } else {
                    expected_chars[0] = ',';
                    expected_chars[1] = '}';
                    continue;
                }
            }
        } else if (!isExpectedChar(char, expected_chars)) {
            error_data.* = JsonErrorData{ .offset = i, .character_at_offset = char, .expected_characters = expected_chars };
            // debugPrint("expected characters {c} or {c}; got {c}\n", .{ expected_chars[0], expected_chars[1], char });
            return JsonError.UnexpectedChar;
        } else if (char == '"') {
            within_string = true;
            continue;
        } else if (char == '{') {
            json_element = .Key;
            brace_depth += 1;
            expected_chars[0] = '\"';
            expected_chars[1] = '\"';
        } else if (char == '}') {
            if (brace_depth == 0) {
                error_data.* = JsonErrorData{ .offset = i, .character_at_offset = char, .expected_characters = expected_chars };
                return JsonError.UnmatchedClosingBrace;
            }
            brace_depth -= 1;
            expected_chars[0] = ',';
            expected_chars[1] = '}';
        } else if (char == ':') {
            json_element = .Value;
            expected_chars[0] = '\"';
            expected_chars[1] = '{';
        } else if (char == ',') {
            json_element = .Key;
            expected_chars[0] = '\"';
            expected_chars[1] = '\"';
        }
    }

    if (brace_depth != 0) {
        return JsonError.UnmatchedOpeningBrace;
    }

    return true;
}

pub fn outputJsonError(error_data: JsonErrorData) !void {
    try stdout.print("error offset: {d}\n", .{error_data.offset});
    try stdout.print("error character at  offset: {c}\n", .{error_data.character_at_offset});
    try stdout.print("error expected characters: {s}\n", .{error_data.expected_characters});
}

/// TESTS
const expect = std.testing.expect;
test "validateJson returns true for valid json" {
    var error_data: ?JsonErrorData = null;
    const valid_json = @embedFile("tragedian.json");

    const is_valid = try validateJson(valid_json, &error_data);
    try expect(is_valid);
    try expect(error_data == null);
}

test "validateJson returns UnexpectedChar and offset correctly" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\"*\"body\":\"black\"}";

    const is_valid = validateJson(unexpected_char_json, &error_data);
    try expect(is_valid == JsonError.UnexpectedChar);
    try expect(error_data.?.offset == 15);
    try expect(error_data.?.character_at_offset == '*');
    try expect(error_data.?.expected_characters[0] == ',');
    try expect(error_data.?.expected_characters[1] == '}');
}

test "validateJson returns UnmatchedOpeningBrace correctly" {
    var error_data: ?JsonErrorData = null;
    const unterminated_string_json = "{\"mask\":\"white\",\"body\":\"black\"";

    const is_valid = validateJson(unterminated_string_json, &error_data);

    // outputJsonError(error_data.?);

    try expect(is_valid == JsonError.UnmatchedOpeningBrace);
}

test "validateJson returns UnmatchedClosingBrace correctly" {
    var error_data: ?JsonErrorData = null;
    const unterminated_string_json = "{\"mask\":\"white\",\"body\":\"black\"}}";

    const is_valid = validateJson(unterminated_string_json, &error_data);

    // outputJsonError(error_data.?);

    try expect(is_valid == JsonError.UnmatchedClosingBrace);
}

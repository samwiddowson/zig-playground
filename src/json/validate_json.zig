const std = @import("std");

const debugPrint = std.debug.print;
const stdout = std.io.getStdOut().writer();

pub const JsonError = error{ CloseOrNewElementNotFound, KeyNotFound, AssignmentNotFound, ValueNotFound, InvalidValue, InvalidNumber, JsonStartNotFound, UnterminatedString };
pub const JsonErrorData = struct { offset: usize, character_at_offset: u8 };

const ReadingJsonElement = enum { key, value };

const CharReaderState = enum { start, string_literal, string_literal_backslash, expect_key, expect_value, expect_assignment, expect_new_or_close };

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
    var array_depth: u16 = 0;

    var reading_json_element: ReadingJsonElement = .key;

    var i: usize = 0;

    read: switch (CharReaderState.start) {
        .start => {
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    i += 1;
                    continue :read .start;
                },
                '{' => {
                    brace_depth += 1;
                    continue :read .expect_key;
                },
                else => {
                    error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                    return JsonError.UnexpectedJsonStart;
                },
            }
        },
        .expect_key => {
            i += 1;
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_key;
                },
                '\"' => {
                    continue :read .string_literal;
                },
                else => {
                    error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                    return JsonError.ExpectedKeyNotFound;
                },
            }
        },
        .string_literal => {
            i += 1;
            switch (buf[i]) {
                0, '\n' => {
                    error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                    return JsonError.UnterminatedString;
                },
                '\"' => {
                    if (reading_json_element == .key) {
                        continue :read .expect_assignment;
                    }
                },
                else => continue :read .string_literal,
            }
        },
        .string_literal_backslash => {
            i += 1;
            switch (buf[i]) {
                0 => {
                    error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                    return JsonError.UnterminatedString;
                },
                else => {
                    continue :read .string_literal;
                },
            }
        },
        .expect_assignment => {
            i += 1;
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_assignment;
                },
                ':' => {
                    reading_json_element = .value;
                    continue :read .expect_value;
                },
                else => {
                    error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                    return JsonError.AssignmentNotFound;
                },
            }
        },
        .expect_value => {
            i += 1;
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_value;
                },
                '\"' => {
                    continue :read .string_literal;
                },
                '0'...'9' => {
                    var decimal_point = false;
                    i += 1;
                    read_number_literal: switch (buf[i]) {
                        '.' => {
                            if (decimal_point) {
                                error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                                return JsonError.InvalidNumber;
                            }
                            decimal_point = true;
                            i += 1;
                            continue :read_number_literal buf[i];
                        },
                        '0'...'9' => {
                            i += 1;
                            continue :read_number_literal buf[i];
                        },
                        else => continue :read .expect_new_or_close,
                    }
                },
                'f' => {
                    if (!std.mem.eql(buf[i..5], "false")) {
                        error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                        return JsonError.InvalidValue;
                    }
                    i += 4; // move index to end of word (safe because we confirmed the word aboved)
                    continue :read .expect_new_or_close;
                },
                't' => {
                    if (!std.mem.eql(buf[i..5], "true")) {
                        error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                        return JsonError.InvalidValue;
                    }
                    i += 3; // move index to end of word (safe because we confirmed the word aboved)
                    continue :read .expect_new_or_close;
                },
                'n' => {
                    if (!std.mem.eql(buf[i..5], "null")) {
                        error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                        return JsonError.ValueNotFound;
                    }
                    i += 3; // move index to end of word (safe because we confirmed the word aboved)
                    continue :read .expect_new_or_close;
                },
                '[' => {
                    array_depth += 1;
                    continue :read .expect_value;
                },
            }
        },
        .expect_new_or_close => {
            i += 1;
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_new_or_close;
                },
                ',' => {
                    std.debug.assert(false); //TODO: implement this
                    //remember array depth
                },
                ']' => {
                    std.debug.assert(false); //TODO: implement this
                    //remember array depth
                },
                '}' => {
                    std.debug.assert(false); //TODO: implement this
                    //remember array depth
                },
                else => {
                    error_data.* = JsonErrorData{ .offset = i, .character_at_offset = buf[i] };
                    return JsonError.CloseOrNewElementNotFound;
                },
            }
        },
    }
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

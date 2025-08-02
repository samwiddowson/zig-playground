const std = @import("std");

const debugPrint = std.debug.print;
const stdout = std.io.getStdOut().writer();

pub const JsonError = error{
    StartNotFound,
    KeyNotFound,
    AssignmentNotFound,
    ValueNotFound,
    InvalidValue,
    InvalidNumber,
    UnterminatedString,
    CloseOrNewElementNotFound,
    UnmatchedSquareBracket,
    EndNotFound,
};

pub const JsonErrorData = struct { offset: usize, character_at_offset: u8 };

const ReadingJsonElement = enum { key, value };

const CharReaderState = enum {
    start,
    string_literal,
    string_literal_backslash,
    expect_key,
    expect_value,
    expect_assignment,
    expect_new_or_close,
    expect_end,
};

/// Some basic Json validation checking
/// This will probably be replaced with the load object function
pub fn validateJson(
    buf: [*:0]const u8,
    error_data: *?JsonErrorData,
) JsonError!void {
    var brace_depth: u16 = 0;
    var array_depth: u16 = 0;

    var reading_json_element: ReadingJsonElement = .key;

    var i: usize = 0;

    read: switch (CharReaderState.start) {
        .start => {
            // debugPrint(".start\n", .{});
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
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i],
                    };
                    return JsonError.StartNotFound;
                },
            }
        },
        .expect_key => {
            // debugPrint(".expect_key\n", .{});
            reading_json_element = .key;
            i += 1;
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_key;
                },
                '\"' => {
                    continue :read .string_literal;
                },
                else => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i],
                    };
                    return JsonError.KeyNotFound;
                },
            }
        },
        .string_literal => {
            // debugPrint(".string_literal {c}\n", .{buf[i]});
            i += 1;
            switch (buf[i]) {
                0, '\n' => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i],
                    };
                    return JsonError.UnterminatedString;
                },
                '\"' => {
                    if (reading_json_element == .key) {
                        continue :read .expect_assignment;
                    }
                    continue :read .expect_new_or_close;
                },
                else => continue :read .string_literal,
            }
        },
        .string_literal_backslash => {
            // debugPrint(".string_literal_bs\n", .{});
            i += 1;
            switch (buf[i]) {
                0 => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i],
                    };
                    return JsonError.UnterminatedString;
                },
                else => {
                    continue :read .string_literal;
                },
            }
        },
        .expect_assignment => {
            // debugPrint(".expect_assignment\n", .{});
            i += 1;
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_assignment;
                },
                ':' => {
                    continue :read .expect_value;
                },
                else => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i],
                    };
                    return JsonError.AssignmentNotFound;
                },
            }
        },
        .expect_value => {
            // debugPrint(".expect_value\n", .{});
            reading_json_element = .value;
            i += 1;
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_value;
                },
                '\"' => {
                    // debugPrint("reading string \n", .{});
                    continue :read .string_literal;
                },
                '0'...'9' => {
                    // debugPrint("reading number {c}\n", .{buf[i]});
                    var decimal_point = false;
                    read_number_literal: switch (buf[i + 1]) {
                        '.' => {
                            if (decimal_point) {
                                error_data.* = JsonErrorData{
                                    .offset = i,
                                    .character_at_offset = buf[i],
                                };
                                return JsonError.InvalidNumber;
                            }
                            decimal_point = true;
                            i += 1;
                            continue :read_number_literal buf[i + 1];
                        },
                        '0'...'9' => {
                            i += 1;
                            continue :read_number_literal buf[i + 1];
                        },
                        ',', ']', '}', '\n' => continue :read .expect_new_or_close,
                        else => {
                            error_data.* = JsonErrorData{
                                .offset = i,
                                .character_at_offset = buf[i],
                            };
                            return JsonError.InvalidNumber;
                        },
                    }
                },
                'f' => {
                    // debugPrint("reading false \n", .{});
                    if (!std.mem.eql(u8, buf[i .. i + 5], "false")) {
                        error_data.* = JsonErrorData{
                            .offset = i,
                            .character_at_offset = buf[i],
                        };
                        return JsonError.InvalidValue;
                    }
                    i += 4; // move index to end of word (safe because we confirmed the word aboved)
                    continue :read .expect_new_or_close;
                },
                't' => {
                    // debugPrint("reading true \n", .{});
                    if (!std.mem.eql(u8, buf[i .. i + 4], "true")) {
                        error_data.* = JsonErrorData{
                            .offset = i,
                            .character_at_offset = buf[i],
                        };
                        return JsonError.InvalidValue;
                    }
                    i += 3; // move index to end of word (safe because we confirmed the word aboved)
                    continue :read .expect_new_or_close;
                },
                'n' => {
                    // debugPrint("reading null \n", .{});
                    if (!std.mem.eql(u8, buf[i .. i + 4], "null")) {
                        error_data.* = JsonErrorData{
                            .offset = i,
                            .character_at_offset = buf[i],
                        };
                        return JsonError.InvalidValue;
                    }
                    i += 3; // move index to end of word (safe because we confirmed the word aboved)
                    continue :read .expect_new_or_close;
                },
                '[' => {
                    array_depth += 1;
                    continue :read .expect_value;
                },
                '{' => {
                    brace_depth += 1;
                    continue :read .expect_key;
                },
                else => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i],
                    };
                    return JsonError.ValueNotFound;
                },
            }
        },
        .expect_new_or_close => {
            // debugPrint(".expect_new_etc\n", .{});
            i += 1;
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_new_or_close;
                },
                ',' => {
                    if (array_depth > 0) {
                        continue :read .expect_value;
                    }
                    continue :read .expect_key;
                },
                ']' => {
                    if (array_depth == 0) {
                        error_data.* = JsonErrorData{
                            .offset = i,
                            .character_at_offset = buf[i],
                        };
                        return JsonError.UnmatchedSquareBracket;
                    }
                    array_depth -= 1;
                    continue :read .expect_new_or_close;
                },
                '}' => {
                    if (brace_depth == 0) {
                        //suspect this can't be reached but still
                        error_data.* = JsonErrorData{
                            .offset = i,
                            .character_at_offset = buf[i],
                        };
                        return JsonError.EndNotFound;
                    }

                    brace_depth -= 1;

                    if (brace_depth > 0) {
                        continue :read .expect_new_or_close;
                    }
                    continue :read .expect_end;
                },
                else => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i],
                    };
                    return JsonError.CloseOrNewElementNotFound;
                },
            }
        },
        .expect_end => {
            // debugPrint(".expect_end\n", .{});
            i += 1;
            switch (buf[i]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_end;
                },
                0 => {
                    // return without error: we found the end where we expected it to be!
                    return;
                },
                else => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i],
                    };
                    return JsonError.EndNotFound;
                },
            }
        },
    }
    debugPrint("Ooooops! Dropped out at index {d}\n", .{i});
    unreachable;
}

pub fn outputJsonError(error_data: JsonErrorData) !void {
    try stdout.print("error offset: {d}\n", .{error_data.offset});
    try stdout.print("error character at  offset: {c}\n", .{error_data.character_at_offset});
}

/// TESTS
const expect = std.testing.expect;
const assert = std.debug.assert;

test "validateJson returns true for valid json" {
    var error_data: ?JsonErrorData = null;
    const valid_json = @embedFile("tragedian.json");

    validateJson(valid_json, &error_data) catch |err| {
        debugPrint("Unexpected error: {}", .{err});
        assert(false);
    };

    try expect(error_data == null);
}

test "validateJson returns StartNotFound when first non-whitespace character is not `{`" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = " \r\n\t\"mask\":\"white\"*\"body\":\"black\"}";
    const err = validateJson(unexpected_char_json, &error_data);
    try expect(err == JsonError.StartNotFound);
    try expect(error_data.?.offset == 4);
    try expect(error_data.?.character_at_offset == '"');
}

test "validateJson returns CloseOrNewElementNotFound when values are not followed by `,` or `}`" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\"*\"body\":\"black\"}";
    const err = validateJson(unexpected_char_json, &error_data);
    try expect(err == JsonError.CloseOrNewElementNotFound);
    try expect(error_data.?.offset == 15);
    try expect(error_data.?.character_at_offset == '*');
}

test "validateJson returns AssignmentNotFound when keys are not followed by `,`" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\"\"white\",\"body\":\"black\"}";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.AssignmentNotFound);
    try expect(error_data.?.offset == 7);
    try expect(error_data.?.character_at_offset == '"');
}

test "validateJson returns KeyNotFound when a string literal is not found at start of a key-value pair" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",body\":\"black\"}";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.KeyNotFound);
    try expect(error_data.?.offset == 16);
    try expect(error_data.?.character_at_offset == 'b');
}

test "validateJson returns InvalidValue when value `true` is misspelled" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",\"body\":\"black\",\"spooky\":ture}";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.InvalidValue);
    try expect(error_data.?.offset == 40);
    try expect(error_data.?.character_at_offset == 't');
}

test "validateJson returns InvalidValue when value `false` is misspelled" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",\"body\":\"black\",\"spooky\":flase}";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.InvalidValue);
    try expect(error_data.?.offset == 40);
    try expect(error_data.?.character_at_offset == 'f');
}

test "validateJson returns InvalidValue when value `null` is misspelled" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",\"body\":\"black\",\"spooky\":nul}";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.InvalidValue);
    try expect(error_data.?.offset == 40);
    try expect(error_data.?.character_at_offset == 'n');
}

test "validateJson returns InvalidNumber when number contains multiple '.' characters" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",\"body\":\"black\",\"pi\":3..14}";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.InvalidNumber);
    try expect(error_data.?.offset == 37);
    try expect(error_data.?.character_at_offset == '.');
}

test "validateJson returns InvalidNumber when number contains invalid characters" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",\"body\":\"black\",\"pi\":3a.14}";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.InvalidNumber);
    try expect(error_data.?.offset == 36);
    try expect(error_data.?.character_at_offset == '3');
}

test "validateJson returns ValueNotFound when unexpected character found instead of value" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",\"body\":\"black\",\"pi\":d";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.ValueNotFound);
    try expect(error_data.?.offset == 36);
    try expect(error_data.?.character_at_offset == 'd');
}

test "validateJson returns UnterminatedString when json body ends in mid string" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",\"body\":\"black\",\"pi\":\"three point one fo";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.UnterminatedString);
    try expect(error_data.?.offset == 55);
    try expect(error_data.?.character_at_offset == 0);
}

test "validateJson returns UnmatchedSquareBracket when attempting to close a non-existant array" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",\"body\":\"black\",\"pi\":3]";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.UnmatchedSquareBracket);
    try expect(error_data.?.offset == 37);
    try expect(error_data.?.character_at_offset == ']');
}

test "validateJson returns EndNotFound when additional non-whitespace characters exist beyond the final closing brace" {
    var error_data: ?JsonErrorData = null;
    const unexpected_char_json = "{\"mask\":\"white\",\"body\":\"black\",\"pi\":3} }";

    const err = validateJson(unexpected_char_json, &error_data);

    try expect(err == JsonError.EndNotFound);
    try expect(error_data.?.offset == 39);
    try expect(error_data.?.character_at_offset == '}');
}

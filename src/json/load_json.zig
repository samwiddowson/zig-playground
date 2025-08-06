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
    UnexpectedKey,
};

const ReadingJsonElement = enum { key, value };

const CharReaderState = enum {
    start,
    string_literal,
    expect_key,
    expect_value,
    expect_assignment,
    expect_new_or_close,
    expect_end,
};

pub const JsonErrorData = struct { offset: usize, character_at_offset: u8 };
pub const LoadErrorData = struct { field_name: [*:0]u8, field_path: [*:0]u8 };

const ErrorData = union { json_error_data: JsonErrorData, load_error_data: LoadErrorData };

pub fn parse_json_object(
    comptime T: type,
    buf: [*:0]const u8,
    error_data: *?ErrorData,
    i: *usize,
) JsonError!T {
    var obj = T{};
    var array_depth: u16 = 0;
    var reading_json_element: ReadingJsonElement = .key;
    var field_name: []const u8 = undefined;

    read: switch (CharReaderState.start) {
        .start => {
            // debugPrint(".start\n", .{});
            switch (buf[i.*]) {
                ' ', '\n', '\r', '\t' => {
                    i.* += 1;
                    continue :read .start;
                },
                '{' => {
                    continue :read .expect_key;
                },
                else => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i.*],
                    };
                    return JsonError.StartNotFound;
                },
            }
        },
        .expect_key => {
            // debugPrint(".expect_key\n", .{});
            reading_json_element = .key;
            i.* += 1;
            switch (buf[i.*]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_key;
                },
                '\"' => {
                    continue :read .string_literal;
                },
                else => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i.*],
                    };
                    return JsonError.KeyNotFound;
                },
            }
        },
        .string_literal => {
            // debugPrint(".string_literal {c}\n", .{buf[i.*]});
            i.* += 1;
            const string_literal_start: usize = i;
            read_string_literal: switch (buf[i.*]) {
                0, '\n' => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i.*],
                    };
                    return JsonError.UnterminatedString;
                },
                '\\' => {
                    i.* += 1;
                    if (buf[i.*] == 0) {
                        error_data.* = JsonErrorData{
                            .offset = i,
                            .character_at_offset = buf[i.*],
                        };
                        return JsonError.UnterminatedString;
                    }
                    // debugPrint("{c}", .{buf[i.*]});
                    i.* += 1;
                    continue :read_string_literal buf[i.*];
                },
                '\"' => {
                    // debugPrint("\n", .{});
                    if (reading_json_element == .key) {
                        field_name = buf[string_literal_start..i.*];
                        if (!@hasField(obj, field_name)) {
                            error_data.* = LoadErrorData{ .field_name = field_name };
                            return JsonError.UnterminatedString;
                        }
                        continue :read .expect_assignment;
                    }
                    @field(obj, field_name) = buf[string_literal_start..i.*];
                    continue :read .expect_new_or_close;
                },
                else => {
                    // debugPrint("{c}", .{buf[i.*]});
                    i.* += 1;
                    continue :read_string_literal buf[i.*];
                },
            }
        },
        .expect_assignment => {
            // debugPrint(".expect_assignment\n", .{});
            i.* += 1;
            switch (buf[i.*]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_assignment;
                },
                ':' => {
                    continue :read .expect_value;
                },
                else => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i.*],
                    };
                    return JsonError.AssignmentNotFound;
                },
            }
        },
        .expect_value => {
            // debugPrint(".expect_value\n", .{});
            reading_json_element = .value;
            i.* += 1;
            switch (buf[i.*]) {
                ' ', '\n', '\r', '\t' => {
                    continue :read .expect_value;
                },
                '\"' => {
                    // debugPrint("reading string \n", .{});
                    continue :read .string_literal;
                },
                '0'...'9' => {
                    // debugPrint("reading number {c}\n", .{buf[i.*]});
                    var decimal_point = false;
                    const number_start: usize = i;
                    const NumberType = @Type(@field(obj, field_name));
                    read_number_literal: switch (buf[i.* + 1]) {
                        '.' => {
                            if (decimal_point) {
                                error_data.* = JsonErrorData{
                                    .offset = i,
                                    .character_at_offset = buf[i],
                                };
                                return JsonError.InvalidNumber;
                            }
                            decimal_point = true;
                            i.* += 1;
                            continue :read_number_literal buf[i.* + 1];
                        },
                        '0'...'9' => {
                            i.* += 1;
                            continue :read_number_literal buf[i.* + 1];
                        },
                        ',', ']', '}', '\n' => {
                            @field(obj, field_name) = try std.fmt.parseInt(NumberType, buf[number_start..i.*], 10);
                            continue :read .expect_new_or_close;
                        },
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
                    if (!std.mem.eql(u8, buf[i.* .. i.* + 5], "false")) {
                        error_data.* = JsonErrorData{
                            .offset = i,
                            .character_at_offset = buf[i],
                        };
                        return JsonError.InvalidValue;
                    }
                    i.* += 4; // move index to end of word (safe because we confirmed the word aboved)
                    @field(obj, field_name) = false;
                    continue :read .expect_new_or_close;
                },
                't' => {
                    // debugPrint("reading true \n", .{});
                    if (!std.mem.eql(u8, buf[i.* .. i.* + 4], "true")) {
                        error_data.* = JsonErrorData{
                            .offset = i,
                            .character_at_offset = buf[i],
                        };
                        return JsonError.InvalidValue;
                    }
                    @field(obj, field_name) = true;
                    i.* += 3; // move index to end of word (safe because we confirmed the word aboved)
                    continue :read .expect_new_or_close;
                },
                'n' => {
                    // debugPrint("reading null \n", .{});
                    if (!std.mem.eql(u8, buf[i.* .. i.* + 4], "null")) {
                        error_data.* = JsonErrorData{
                            .offset = i,
                            .character_at_offset = buf[i],
                        };
                        return JsonError.InvalidValue;
                    }
                    @field(obj, field_name) = null;
                    i += 3; // move index to end of word (safe because we confirmed the word aboved)
                    continue :read .expect_new_or_close;
                },
                '[' => {
                    std.debug.print("Array parsing is not yet implemented!", .{});
                    std.debug.assert(false);
                    array_depth += 1;
                    continue :read .expect_value;
                },
                '{' => {
                    @field(obj, field_name) = parse_json_object(@Type(@field(obj, field_name)), buf, error_data, &i);
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
            switch (buf[i.*]) {
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
                            .character_at_offset = buf[i.*],
                        };
                        return JsonError.UnmatchedSquareBracket;
                    }
                    array_depth -= 1;
                    continue :read .expect_new_or_close;
                },
                '}' => {
                    return obj;
                },
                else => {
                    error_data.* = JsonErrorData{
                        .offset = i,
                        .character_at_offset = buf[i.*],
                    };
                    return JsonError.CloseOrNewElementNotFound;
                },
            }
        },
    }
    debugPrint("Ooooops! Dropped out at index {d}\n", .{i});
    unreachable;
}

pub fn load_json_object(
    comptime T: type,
    buf: [*:0]const u8,
    error_data: *?ErrorData,
) !T {
    var i: usize = 0;
    const obj = parse_json_object(T, buf, error_data, &i);
    while (buf[i] != 0) : (i += 1) {
        // debugPrint("check end\n", .{});
        switch (buf[i]) {
            ' ', '\n', '\r', '\t' => {
                continue;
            },
            0 => {
                // return without error: we found the end where we expected it to be!
                return obj;
            },
            else => {
                error_data.* = JsonErrorData{
                    .offset = i,
                    .character_at_offset = buf[i],
                };
                return JsonError.EndNotFound;
            },
        }
    }
    unreachable;
}

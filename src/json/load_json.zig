const std = @import("std");
const jsonValidator = @import("validate_json.zig");

const stdout = std.io.getStdOut().writer();

pub const JsonLoadError = error{ UnmatchedClosingBrace, UnmatchedOpeningBrace, UnexpectedChar, UnterminatedString, LoadError };
pub const JsonErrorData = struct { offset: usize, character_at_offset: u8, expected_characters: [2]u8 };
pub const LoadErrorData = struct { field_name: [*:0]u8, field_path: [*:0]u8 };

const ErrorData = union { json_error_data: JsonErrorData, load_error_data: LoadErrorData };

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

fn getStringVal(buf: [*:0]u8, str: []u8, i: *usize) JsonLoadError!void {
    const opening_offset = i.*;
    i.* += 1;
    while(buf[i.*] != '"'): (i.* += 1) {
        if(buf[i.*] == 0 or buf[i.*] == '\n') {
            return JsonLoadError.UnterminatedString;
        }
    }
    str = buf[opening_offset..i.*];
}

pub fn load_json_object(
    comptime T: type,
    buf: [*:0]const u8,
    error_data: *?ErrorData,
) !T {
    var loaded_obj: T = T{};
    // each json key:
    // - check @hasField(T, "keyname");
    // - throw err if not
    // - put value into T.keyname with @field(T, "keyname") = val
    //
    var brace_depth: u16 = 0;
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

        if (!isExpectedChar(char, expected_chars)) {
            error_data.* = JsonErrorData{ .offset = i, .character_at_offset = char, .expected_characters = expected_chars };
            // debugPrint("expected characters {c} or {c}; got {c}\n", .{ expected_chars[0], expected_chars[1], char });
            return JsonLoadError.UnexpectedChar;
        } else if (char == '"') {
            if(json_element == .Key) {
                var key: []u8 = undefined;
                getStringVal(buf, &i, &key) catch |err| {
                    error_data.* = JsonErrorData {
                        .offset = i,
                        .character_at_offset = buf[i]
                    };
            };
                if(!@hasField(T, key)){
                    return JsonLoadError.LoadError;
                }
            }
        }
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

const std = @import("std");
const jsonValidator = @import("validate_json.zig");

const stdout = std.io.getStdOut().writer();

pub fn load_json_object(
    comptime T: type,
) !T {
    // each json key:
    // - check @hasField(T, "keyname");
    // - throw err if not
    // - put value into T.keyname with @field(T, "keyname") = val
    //
}

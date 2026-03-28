//! Unicode decoding, validation, and counting primitives.
//!
//! The implementation in this file is extracted from `runerip`, with
//! the public surface reorganized into encoding namespaces.

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

// zig fmt: off

/// Byte transitions: value to class
const u8dfa: [256]u8 = .{
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00..1f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20..3f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40..5f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60..7f
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 80..9f
7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0..bf
8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0..df
0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, // e0..ef
0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, // f0..ff
};

const w8dfa: [256]u8 = .{
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00..1f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20..3f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40..5f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60..7f
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 80..9f
7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0..bf
8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0..df
0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, // e0..ef
0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, // f0..ff
};

/// State transition: state + class = new state
const st_dfa: [108]u8 = .{
 0,12,24,36,60,96,84,12,12,12,48,72,
12,12,12,12,12,12,12,12,12,12,12,12,
12, 0,12,12,12,12,12, 0,12, 0,12,12,
12,24,12,12,12,12,12,24,12,24,12,12,
12,12,12,12,12,12,12,24,12,12,12,12,
12,24,12,12,12,12,12,12,12,24,12,12,
12,12,12,12,12,12,12,36,12,36,12,12,
12,36,12,12,12,12,12,36,12,36,12,12,
12,36,12,12,12,12,12,12,12,12,12,12,
};

/// State masks
const c_mask: [12]u8 = .{
    0xff,
    0,
    0b0011_1111,
    0b0001_1111,
    0b0000_1111,
    0b0000_0111,
    0b0000_0011,
    0,
    0,
    0,
    0,
    0,
};

// zig fmt: on

/// Successful codepoint parse
pub const UTF_ACCEPT = 0;

/// Error state
pub const UTF_REJECT = 12;

pub const utf8 = struct {
    pub const Error = error{InvalidUtf8};

    /// Decode the codepoint at `slice[0]`.
    /// Assumes that `slice.len > 0`.
    pub fn decode(slice: []const u8) Error!u21 {
        return decodeRune(slice);
    }

    /// Decode the codepoint at `slice[cursor.*]`.
    /// The cursor is advanced to one index past the decoded codepoint,
    /// which may include `slice.len`. On error, the cursor points to
    /// the first invalid byte in the sequence. Asserts that `cursor.*`
    /// indexes `slice`.
    pub fn decodeCursor(slice: []const u8, cursor: *usize) Error!u21 {
        return decodeRuneCursor(slice, cursor);
    }

    /// Return whether `slice` is valid UTF-8.
    pub fn validateSlice(slice: []const u8) bool {
        return validateRuneSlice(slice);
    }

    /// Return whether `slice` is valid UTF-8.
    /// On success, `cursor` is advanced to `slice.len`. On failure,
    /// it points to the first rejected byte.
    pub fn validateSliceCursor(slice: []const u8, cursor: *usize) bool {
        return validateRuneCursor(slice, cursor);
    }

    /// Count the number of UTF-8 codepoints in `slice`.
    pub fn countCodepoints(slice: []const u8) Error!usize {
        return countRunes(slice);
    }
};

pub const wtf8 = struct {
    pub const Error = error{InvalidWtf8};

    pub fn decode(slice: []const u8) Error!u21 {
        var cursor: usize = 0;
        return decodeCursor(slice, &cursor);
    }

    pub fn decodeCursor(slice: []const u8, cursor: *usize) Error!u21 {
        return decodeAnyRuneCursor(w8dfa, st_dfa, c_mask, slice, cursor) catch {
            return error.InvalidWtf8;
        };
    }

    pub fn validateSlice(slice: []const u8) bool {
        return validateRuneSliceWtf8(slice);
    }

    pub fn validateSliceCursor(slice: []const u8, cursor: *usize) bool {
        return validateRuneWtf8Cursor(slice, cursor);
    }

    pub fn countCodepoints(slice: []const u8) Error!usize {
        return countRunesWtf8(slice) catch {
            return error.InvalidWtf8;
        };
    }
};

pub fn countCodepointsAssumeValid(slice: []const u8) usize {
    return countValidRunes(slice);
}

/// Decode a rune at ``slice[0]`.  Assumes that `slice.len > 0`.
fn decodeRune(slice: []const u8) !u21 {
    var cursor: usize = 0;
    return decodeRuneCursor(slice, &cursor);
}

/// Decode a rune at `slice[cursor.*]`.  The cursor will be advanced to
/// one index past the decoded rune, which may include `slice.len`.  If
/// an error is thrown the cursor will point to the first invalid byte
/// in the sequence.  Asserts that `slice` is indexable at `cursor.*`.
fn decodeRuneCursor(slice: []const u8, cursor: *usize) !u21 {
    return decodeAnyRuneCursor(u8dfa, st_dfa, c_mask, slice, cursor);
}

fn decodeAnyRuneCursor(
    cu_dfa: anytype,
    state_dfa: anytype,
    class_mask: anytype,
    slice: []const u8,
    i: *usize,
) !u21 {
    assert(i.* < slice.len);
    var byte: u16 = slice[i.*];
    if (byte < 0x80) {
        i.* += 1;
        return byte;
    }
    // Multibyte
    var class: u4 = @intCast(cu_dfa[byte]);
    var st: u32 = state_dfa[class];
    var rune: u32 = byte & class_mask[class];
    if (st == UTF_REJECT) return error.InvalidUtf8;
    i.* += 1;
    switch (class) {
        2, 12 => if (i.* + 1 > slice.len) {
            return error.InvalidUtf8;
        },
        10, 3, 4 => if (i.* + 2 > slice.len) {
            return error.InvalidUtf8;
        },
        11, 6, 5 => if (i.* + 3 > slice.len) {
            return error.InvalidUtf8;
        }, // Remaining states are ACCEPT or produce REJECT here
        else => unreachable,
    }
    // Byte 2
    byte = slice[i.*];
    class = @intCast(u8dfa[byte]);
    st = state_dfa[st + class];
    rune = (byte & 0x3f) | (rune << 6);
    if (st == UTF_REJECT) return error.InvalidUtf8;
    i.* += 1;
    if (st == UTF_ACCEPT) return @intCast(rune);
    // Byte 3
    byte = slice[i.*];
    class = @intCast(u8dfa[byte]);
    st = state_dfa[st + class];
    rune = (byte & 0x3f) | (rune << 6);
    if (st == UTF_REJECT) return error.InvalidUtf8;
    i.* += 1;
    if (st == UTF_ACCEPT) return @intCast(rune);
    // Byte 4
    byte = slice[i.*];
    class = @intCast(u8dfa[byte]);
    st = state_dfa[st + class];
    rune = (byte & 0x3f) | (rune << 6);
    if (st != UTF_ACCEPT) return error.InvalidUtf8;
    i.* += 1;
    return @intCast(rune);
}

fn countRunes(slice: []const u8) !usize {
    return countAnyRunes(u8dfa, st_dfa, slice);
}

fn countRunesWtf8(slice: []const u8) !usize {
    return countAnyRunes(w8dfa, st_dfa, slice);
}

fn countAnyRunes(cu_dfa: anytype, state_dfa: anytype, slice: []const u8) !usize {
    var st: u32 = 0;
    var i: usize = 0;
    var class: u8 = 0;
    var count: usize = 0;
    while (i < slice.len) : (i += 1) {
        assert(st == UTF_ACCEPT);
        count += 1;
        const b = slice[i];
        if (b < 0x80) continue;
        class = cu_dfa[b];
        st = state_dfa[class];
        if (st == UTF_REJECT) return error.InvalidUtf8;
        switch (class) {
            2, 12 => if (i + 2 > slice.len) {
                return error.InvalidUtf8;
            },
            10, 3, 4 => if (i + 3 > slice.len) {
                return error.InvalidUtf8;
            },
            11, 6, 5 => if (i + 4 > slice.len) {
                return error.InvalidUtf8;
            }, // Remaining states are ACCEPT or produce REJECT here
            else => unreachable,
        }
        i += 1;
        st = state_dfa[st + cu_dfa[slice[i]]];
        if (st == UTF_ACCEPT) continue;
        if (st == UTF_REJECT) return error.InvalidUtf8;
        i += 1;
        st = state_dfa[st + cu_dfa[slice[i]]];
        if (st == UTF_ACCEPT) continue;
        if (st == UTF_REJECT) return error.InvalidUtf8;
        i += 1;
        st = state_dfa[st + cu_dfa[slice[i]]];
        if (st == UTF_REJECT) return error.InvalidUtf8;
    }
    return count;
}

const weight: [4]u8 = .{ 1, 1, 0, 1 };

/// Count the number of runes in an assumed-valid slice.  This gives correct
/// answers for either of WTF-8 or UTF-8, provided that the string is valid by
/// either standard.  Invalid data will give a spurious answer, but is otherwise
/// safe to provide.
fn countValidRunes(slice: []const u8) usize {
    var c: usize = 0;
    for (slice) |b| {
        c += weight[b >> 6];
    }
    return c;
}

/// Validate that a slice is composed only of valid runes in the
/// UTF-8 encoding.
fn validateRuneSlice(slice: []const u8) bool {
    var i: usize = 0;
    return validateAnyRuneWithCursor(u8dfa, st_dfa, slice, &i);
}

/// Validate that a slice is composed only of valid runes in the
/// WTF-8 encoding.
fn validateRuneSliceWtf8(slice: []const u8) bool {
    var i: usize = 0;
    return validateAnyRuneWithCursor(w8dfa, st_dfa, slice, &i);
}

/// UTF-8 encoding.  Must be passed a cursor, by pointer: this
/// will point to slice.len when the return value is `true`, and
/// to the first rejected byte when `false`.
fn validateRuneCursor(slice: []const u8, i: *usize) bool {
    return validateAnyRuneWithCursor(u8dfa, st_dfa, slice, i);
}

/// Validate that a slice is composed only of valid runes in the
/// WTF-8 encoding.  Must be passed a cursor, by pointer: this
/// will point to slice.len when the return value is `true`, and
/// to the first rejected byte when `false`.
fn validateRuneWtf8Cursor(slice: []const u8, i: *usize) bool {
    return validateAnyRuneWithCursor(w8dfa, st_dfa, slice, i);
}

fn validateAnyRuneWithCursor(
    cu_dfa: anytype,
    state_dfa: anytype,
    slice: []const u8,
    i: *usize,
) bool {
    var st: u32 = 0;
    var class: u8 = 0;
    while (i.* < slice.len) : (i.* += 1) {
        assert(st == UTF_ACCEPT);
        const b = slice[i.*];
        if (b < 0x80) continue;
        class = cu_dfa[b];
        st = state_dfa[class];
        if (st == UTF_REJECT) return false;
        switch (class) {
            0, 1 => unreachable,
            2, 12 => if (i.* + 2 > slice.len) {
                return false;
            },
            10, 3, 4 => if (i.* + 3 > slice.len) {
                return false;
            },
            11, 6, 5 => if (i.* + 4 > slice.len) {
                return false;
            },
            else => unreachable,
        }
        i.* += 1;
        st = state_dfa[st + cu_dfa[slice[i.*]]];
        if (st == UTF_ACCEPT) continue;
        if (st == UTF_REJECT) return false;
        i.* += 1;
        st = state_dfa[st + cu_dfa[slice[i.*]]];
        if (st == UTF_ACCEPT) continue;
        if (st == UTF_REJECT) return false;
        i.* += 1;
        st = state_dfa[st + cu_dfa[slice[i.*]]];
        if (st == UTF_REJECT) return false;
    }
    return true;
}

const ascii = "abcde";
const greek = "αβγδε";
const mixed = "aβ∅🤓";
test "utf8.decode handles ascii and multibyte codepoints" {
    try testing.expectEqual(@as(u21, 'a'), try utf8.decode("abc"));
    try testing.expectEqual(@as(u21, 0x03B1), try utf8.decode("α"));
    try testing.expectEqual(@as(u21, 0x2205), try utf8.decode("∅"));
    try testing.expectEqual(@as(u21, 0x1F913), try utf8.decode("🤓"));
}

test "utf8.decodeCursor advances through a string" {
    var cursor: usize = 0;

    try testing.expectEqual(@as(u21, 'a'), try utf8.decodeCursor(mixed, &cursor));
    try testing.expectEqual(@as(usize, 1), cursor);
    try testing.expectEqual(@as(u21, 0x03B2), try utf8.decodeCursor(mixed, &cursor));
    try testing.expectEqual(@as(usize, 3), cursor);
    try testing.expectEqual(@as(u21, 0x2205), try utf8.decodeCursor(mixed, &cursor));
    try testing.expectEqual(@as(usize, 6), cursor);
    try testing.expectEqual(@as(u21, 0x1F913), try utf8.decodeCursor(mixed, &cursor));
    try testing.expectEqual(mixed.len, cursor);
}

test "utf8.validateSlice and countCodepoints accept valid input" {
    try testing.expect(utf8.validateSlice(ascii));
    try testing.expect(utf8.validateSlice(greek));
    try testing.expect(utf8.validateSlice(mixed));

    try testing.expectEqual(@as(usize, 5), try utf8.countCodepoints(ascii));
    try testing.expectEqual(@as(usize, 5), try utf8.countCodepoints(greek));
    try testing.expectEqual(@as(usize, 4), try utf8.countCodepoints(mixed));
}

test "utf8 invalid data reports the first bad byte" {
    const invalid = "a\xf0\x28\x8c\xbc";

    var validate_cursor: usize = 0;
    try testing.expect(!utf8.validateSliceCursor(invalid, &validate_cursor));
    try testing.expectEqual(@as(usize, 2), validate_cursor);

    var decode_cursor: usize = 1;
    try testing.expectError(error.InvalidUtf8, utf8.decodeCursor(invalid, &decode_cursor));
    try testing.expectEqual(@as(usize, 2), decode_cursor);
}

test "utf8 rejects truncated sequences" {
    const truncated = "\xf0\x9f\x92";

    try testing.expect(!utf8.validateSlice(truncated));
    try testing.expectError(error.InvalidUtf8, utf8.countCodepoints(truncated));

    var cursor: usize = 0;
    try testing.expectError(error.InvalidUtf8, utf8.decodeCursor(truncated, &cursor));
    try testing.expectEqual(@as(usize, 1), cursor);
}

test "wtf8 namespace matches shared valid utf8 behavior" {
    try testing.expect(wtf8.validateSlice(greek));
    try testing.expectEqual(@as(usize, 5), try wtf8.countCodepoints(greek));
    try testing.expectEqual(@as(u21, 0x03B1), try wtf8.decode("α"));

    var cursor: usize = 0;
    try testing.expectEqual(@as(u21, 'a'), try wtf8.decodeCursor(mixed, &cursor));
    try testing.expectEqual(@as(usize, 1), cursor);
}

test "countCodepointsAssumeValid matches valid utf8 and wtf8 slices" {
    try testing.expectEqual(try utf8.countCodepoints(greek), countCodepointsAssumeValid(greek));
    try testing.expectEqual(try utf8.countCodepoints(mixed), countCodepointsAssumeValid(mixed));
    try testing.expectEqual(try wtf8.countCodepoints(greek), countCodepointsAssumeValid(greek));
}

test "wtf8 wrappers remap malformed input to InvalidWtf8" {
    const invalid = "\xf0\x28\x8c\xbc";

    try testing.expect(!wtf8.validateSlice(invalid));
    try testing.expectError(error.InvalidWtf8, wtf8.countCodepoints(invalid));

    var cursor: usize = 0;
    try testing.expectError(error.InvalidWtf8, wtf8.decodeCursor(invalid, &cursor));
}

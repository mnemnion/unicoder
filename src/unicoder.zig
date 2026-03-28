//! Unicode decoding, validation, and counting primitives.
//!
//! The implementation in this file is extracted from `runerip`, with
//! the public surface reorganized into encoding namespaces.

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
const UTF_ACCEPT = 0;

/// Error state
const UTF_REJECT = 12;

const ErrorStrategyKind = enum {
    exact,
    lossy,
    assume_valid,
};

const Xf8Kind = enum {
    utf8,
    wtf8,
};

/// Operations onto, and out of, the UTF-8 encoding.
pub const utf8 = struct {
    /// Error returned when invalid Unicode is encountered.
    pub const Error = error{InvalidUtf8};

    /// A "view" into a Utf8 string.  Comes in several kinds.
    pub const Utf8View = Xf8View(.utf8);

    /// The strategy for error handling of a given Utf8View.
    pub const ErrorStrategy = ErrorStrategyKind;

    /// The "lossy" version of the library.  Same functionality
    /// as the base, but errors are handled using Substitution of
    /// Maximal Subparts, returning U+FFD for the offending region.
    pub const lossy = utf8_lossy;

    /// The "valid" version of the library.  Same functionality
    /// as the base, but assumes inputs are already valid UTF-8.
    /// Bad things will reliably happen if this assumption is not
    /// correct.
    pub const valid = utf8_assume_valid;

    /// Wrap a byte slice as a UTF-8 view specialized to the selected error strategy.
    pub fn iterator(slice: []const u8, comptime strategy: ErrorStrategy) Utf8View(strategy) {
        return Utf8View(strategy).init(slice);
    }

    /// Decode the codepoint at `slice[0]`.
    /// Assumes that `slice.len > 0`.
    pub fn decode(slice: []const u8) Error!u21 {
        return decodeXtf8(slice);
    }

    /// Decode the codepoint at `slice[cursor.*]`.
    /// The cursor is advanced to one index past the decoded codepoint,
    /// which may include `slice.len`. On error, the cursor points to
    /// the first invalid byte in the sequence. Asserts that `cursor.*`
    /// indexes `slice`.
    pub fn decodeCursor(slice: []const u8, cursor: *usize) Error!u21 {
        return decodeXtf8Cursor(slice, cursor);
    }

    /// Return whether `slice` is valid UTF-8.
    pub fn validate(slice: []const u8) bool {
        return validateXtf8(slice);
    }

    /// Return whether `slice` is valid UTF-8.
    /// On success, `cursor` is advanced to `slice.len`. On failure,
    /// it points to the first rejected byte.
    pub fn validateCursor(slice: []const u8, cursor: *usize) bool {
        return validateXtf8Cursor(slice, cursor);
    }

    /// Count the number of UTF-8 codepoints in `slice`.
    pub fn countCodepoints(slice: []const u8) Error!usize {
        return countXtf8(slice);
    }

    /// Transcode UTF-8 source into UTF-16LE destination, returning the
    /// number of code units written. Assumes that the destination has
    /// sufficient room for the transcoding.
    pub fn toUtf16Le(utf_16: []u16, utf_8: []const u8) Error!usize {
        return utf8ToUtf16Le(utf_16, utf_8);
    }

    /// Transcode UTF-8 source into UTF-16BE destination, returning the
    /// number of code units written. Assumes that the destination has
    /// sufficient room for the transcoding.
    pub fn toUtf16Be(utf_16: []u16, utf_8: []const u8) Error!usize {
        return utf8ToUtf16Be(utf_16, utf_8);
    }

    /// Transcode UTF-8 source into UTF-16LE destination.
    /// On error, `i_16` points just past the last transcoded code unit
    /// and `i_8` points to the source of the error. On success, `i_16`
    /// points to the code unit position that may be sliced to obtain the result.
    pub fn toUtf16LeCursor(utf_16: []u16, utf_8: []const u8, i_16: *usize, i_8: *usize) Error!void {
        return utf8ToUtf16LeCursor(utf_16, utf_8, i_16, i_8);
    }

    /// Transcode UTF-8 source into UTF-16BE destination.
    /// On error, `i_16` points just past the last transcoded code unit
    /// and `i_8` points to the source of the error. On success, `i_16`
    /// points to the code unit position that may be sliced to obtain the result.
    pub fn toUtf16BeCursor(utf_16: []u16, utf_8: []const u8, i_16: *usize, i_8: *usize) Error!void {
        return utf8ToUtf16BeCursor(utf_16, utf_8, i_16, i_8);
    }
};

/// Operations onto, and out of, the wtf8 encoding.  See:
/// https://wtf-8.codeberg.page/
pub const wtf8 = struct {
    /// Error returned when invalid Unicode is encountered.
    pub const Error = error{InvalidWtf8};

    /// A "view" into a Wtf8 string.  Comes in several kinds.
    pub const Wtf8View = Xf8View(.wtf8);

    /// The strategy for error handling of a given Wtf8View.
    pub const ErrorStrategy = ErrorStrategyKind;

    /// The "lossy" version of the library.  Same functionality
    /// as the base, but errors are handled using Substitution of
    /// Maximal Subparts, returning U+FFD for the offending region.
    pub const lossy = wtf8_lossy;

    /// The "valid" version of the library.  Same functionality
    /// as the base, but assumes inputs are already valid WTF-8.
    /// Bad things will reliably happen if this assumption is not
    /// correct.
    pub const valid = wtf8_assume_valid;

    /// Wrap a byte slice as a WTF-8 view specialized to the selected error strategy.
    pub fn iterator(slice: []const u8, comptime strategy: ErrorStrategy) Wtf8View(strategy) {
        return Wtf8View(strategy).init(slice);
    }

    /// Decode the codepoint at `slice[0]`.
    /// Assumes that `slice.len > 0`.
    pub fn decode(slice: []const u8) Error!u21 {
        var cursor: usize = 0;
        return decodeCursor(slice, &cursor);
    }

    /// Decode the codepoint at `slice[cursor.*]`.
    /// The cursor is advanced to one index past the decoded codepoint,
    /// which may include `slice.len`. On error, the cursor points to
    /// the first invalid byte in the sequence. Asserts that `cursor.*`
    /// indexes `slice`.
    pub fn decodeCursor(slice: []const u8, cursor: *usize) Error!u21 {
        return decodeAnyXtf8Cursor(w8dfa, st_dfa, c_mask, slice, cursor) catch {
            return error.InvalidWtf8;
        };
    }

    /// Return whether `slice` is valid WTF-8.
    pub fn validate(slice: []const u8) bool {
        return validateWtf8(slice);
    }

    /// Return whether `slice` is valid WTF-8.
    /// On success, `cursor` is advanced to `slice.len`. On failure,
    /// it points to the first rejected byte.
    pub fn validateCursor(slice: []const u8, cursor: *usize) bool {
        return validateWtf8Cursor(slice, cursor);
    }

    /// Count the number of WTF-8 codepoints in `slice`.
    pub fn countCodepoints(slice: []const u8) Error!usize {
        return countWtf8(slice) catch {
            return error.InvalidWtf8;
        };
    }

    /// Transcode WTF-8 source into WTF-16LE destination, returning the
    /// number of code units written. Assumes that the destination has
    /// sufficient room for the transcoding.
    pub fn toWtf16Le(wtf_16: []u16, wtf_8: []const u8) Error!usize {
        return wtf8ToWtf16Le(wtf_16, wtf_8) catch {
            return error.InvalidWtf8;
        };
    }

    /// Transcode WTF-8 source into WTF-16BE destination, returning the
    /// number of code units written. Assumes that the destination has
    /// sufficient room for the transcoding.
    pub fn toWtf16Be(wtf_16: []u16, wtf_8: []const u8) Error!usize {
        return wtf8ToWtf16Be(wtf_16, wtf_8) catch {
            return error.InvalidWtf8;
        };
    }

    /// Transcode WTF-8 source into WTF-16LE destination.
    /// On error, `i_16` points just past the last transcoded code unit
    /// and `i_8` points to the source of the error. On success, `i_16`
    /// points to the code unit position that may be sliced to obtain the result.
    pub fn toWtf16LeCursor(wtf_16: []u16, wtf_8: []const u8, i_16: *usize, i_8: *usize) Error!void {
        return wtf8ToWtf16LeCursor(wtf_16, wtf_8, i_16, i_8) catch {
            return error.InvalidWtf8;
        };
    }

    /// Transcode WTF-8 source into WTF-16BE destination.
    /// On error, `i_16` points just past the last transcoded code unit
    /// and `i_8` points to the source of the error. On success, `i_16`
    /// points to the code unit position that may be sliced to obtain the result.
    pub fn toWtf16BeCursor(wtf_16: []u16, wtf_8: []const u8, i_16: *usize, i_8: *usize) Error!void {
        return wtf8ToWtf16BeCursor(wtf_16, wtf_8, i_16, i_8) catch {
            return error.InvalidWtf8;
        };
    }
};

const utf8_lossy = struct {
    /// Decode the codepoint at `slice[0]`, substituting U+FFFD for malformed input.
    /// `slice.len` must not be `0`.
    pub fn decode(slice: []const u8) u21 {
        var cursor: usize = 0;
        return decodeCursor(slice, &cursor);
    }

    /// Decode the codepoint at `slice[cursor.*]`, substituting U+FFFD for malformed input.
    /// The cursor advances by the consumed maximal subpart.
    pub fn decodeCursor(slice: []const u8, cursor: *usize) u21 {
        return decodeAnyLossyXtf8Cursor(u8dfa, st_dfa, c_mask, slice, cursor);
    }

    /// Return whether `slice` is valid UTF-8.
    pub fn validate(slice: []const u8) bool {
        return validateXtf8(slice);
    }

    /// Return whether `slice` is valid UTF-8.
    /// On success, `cursor` is advanced to `slice.len`. On failure,
    /// it points to the first rejected byte.
    pub fn validateCursor(slice: []const u8, cursor: *usize) bool {
        return validateXtf8Cursor(slice, cursor);
    }

    /// Count the number of codepoints emitted by lossy UTF-8 decoding.
    pub fn countCodepoints(slice: []const u8) usize {
        return countAnyLossyCps(u8dfa, slice);
    }

    /// Transcode UTF-8 source into UTF-16LE destination, substituting U+FFFD for malformed input.
    pub fn toUtf16Le(utf_16: []u16, utf_8: []const u8) usize {
        var i_8: usize = 0;
        var i_16: usize = 0;
        return xtf8LossyToXtf16(true, u8dfa, st_dfa, c_mask, utf_16, utf_8, &i_16, &i_8);
    }

    /// Transcode UTF-8 source into UTF-16BE destination, substituting U+FFFD for malformed input.
    pub fn toUtf16Be(utf_16: []u16, utf_8: []const u8) usize {
        var i_8: usize = 0;
        var i_16: usize = 0;
        return xtf8LossyToXtf16(false, u8dfa, st_dfa, c_mask, utf_16, utf_8, &i_16, &i_8);
    }

    /// Transcode UTF-8 source into UTF-16LE destination, substituting U+FFFD for malformed input.
    pub fn toUtf16LeCursor(utf_16: []u16, utf_8: []const u8, i_16: *usize, i_8: *usize) void {
        _ = xtf8LossyToXtf16(true, u8dfa, st_dfa, c_mask, utf_16, utf_8, i_16, i_8);
    }

    /// Transcode UTF-8 source into UTF-16BE destination, substituting U+FFFD for malformed input.
    pub fn toUtf16BeCursor(utf_16: []u16, utf_8: []const u8, i_16: *usize, i_8: *usize) void {
        _ = xtf8LossyToXtf16(false, u8dfa, st_dfa, c_mask, utf_16, utf_8, i_16, i_8);
    }
};

const wtf8_lossy = struct {
    /// Decode the codepoint at `slice[0]`, substituting U+FFFD for malformed input.
    /// `slice.len` must not be `0`.
    pub fn decode(slice: []const u8) u21 {
        var cursor: usize = 0;
        return decodeCursor(slice, &cursor);
    }

    /// Decode the codepoint at `slice[cursor.*]`, substituting U+FFFD for malformed input.
    /// The cursor advances by the consumed maximal subpart.
    pub fn decodeCursor(slice: []const u8, cursor: *usize) u21 {
        return decodeAnyLossyXtf8Cursor(w8dfa, st_dfa, c_mask, slice, cursor);
    }

    /// Return whether `slice` is valid WTF-8.
    pub fn validate(slice: []const u8) bool {
        return validateWtf8(slice);
    }

    /// Return whether `slice` is valid WTF-8.
    /// On success, `cursor` is advanced to `slice.len`. On failure,
    /// it points to the first rejected byte.
    pub fn validateCursor(slice: []const u8, cursor: *usize) bool {
        return validateWtf8Cursor(slice, cursor);
    }

    /// Count the number of codepoints emitted by lossy WTF-8 decoding.
    pub fn countCodepoints(slice: []const u8) usize {
        return countAnyLossyCps(w8dfa, slice);
    }

    /// Transcode WTF-8 source into WTF-16LE destination, substituting U+FFFD for malformed input.
    pub fn toWtf16Le(wtf_16: []u16, wtf_8: []const u8) usize {
        var i_8: usize = 0;
        var i_16: usize = 0;
        return xtf8LossyToXtf16(true, w8dfa, st_dfa, c_mask, wtf_16, wtf_8, &i_16, &i_8);
    }

    /// Transcode WTF-8 source into WTF-16BE destination, substituting U+FFFD for malformed input.
    pub fn toWtf16Be(wtf_16: []u16, wtf_8: []const u8) usize {
        var i_8: usize = 0;
        var i_16: usize = 0;
        return xtf8LossyToXtf16(false, w8dfa, st_dfa, c_mask, wtf_16, wtf_8, &i_16, &i_8);
    }

    /// Transcode WTF-8 source into WTF-16LE destination, substituting U+FFFD for malformed input.
    pub fn toWtf16LeCursor(wtf_16: []u16, wtf_8: []const u8, i_16: *usize, i_8: *usize) void {
        _ = xtf8LossyToXtf16(true, w8dfa, st_dfa, c_mask, wtf_16, wtf_8, i_16, i_8);
    }

    /// Transcode WTF-8 source into WTF-16BE destination, substituting U+FFFD for malformed input.
    pub fn toWtf16BeCursor(wtf_16: []u16, wtf_8: []const u8, i_16: *usize, i_8: *usize) void {
        _ = xtf8LossyToXtf16(false, w8dfa, st_dfa, c_mask, wtf_16, wtf_8, i_16, i_8);
    }
};

const utf8_assume_valid = struct {
    /// Decode the codepoint at `slice[0]`.
    /// Assumes that `slice` begins with a valid UTF-8 codepoint.
    pub fn decode(slice: []const u8) u21 {
        return decodeXtf8AssumeValid(slice);
    }

    /// Decode the codepoint at `slice[cursor.*]`.
    /// Assumes that `cursor` points at a valid UTF-8 codepoint.
    pub fn decodeCursor(slice: []const u8, cursor: *usize) u21 {
        return decodeAnyXtf8AssumeValidCursor(u8dfa, c_mask, slice, cursor);
    }

    /// Return whether `slice` is valid UTF-8.
    pub fn validate(slice: []const u8) bool {
        return validateXtf8(slice);
    }

    /// Return whether `slice` is valid UTF-8.
    /// On success, `cursor` is advanced to `slice.len`. On failure,
    /// it points to the first rejected byte.
    pub fn validateCursor(slice: []const u8, cursor: *usize) bool {
        return validateXtf8Cursor(slice, cursor);
    }

    /// Count the number of UTF-8 codepoints in `slice`.
    /// Assumes that `slice` is already valid UTF-8.
    pub fn countCodepoints(slice: []const u8) usize {
        return countCodepointsAssumeValid(slice);
    }

    /// Transcode UTF-8 source into UTF-16LE destination, returning the
    /// number of code units written. Assumes that source is valid UTF-8
    /// and the destination has sufficient room for the transcoding.
    pub fn toUtf16Le(utf_16: []u16, utf_8: []const u8) usize {
        var i_8: usize = 0;
        var i_16: usize = 0;
        return xtf8AssumeValidToXtf16(true, u8dfa, c_mask, utf_16, utf_8, &i_16, &i_8);
    }

    /// Transcode UTF-8 source into UTF-16BE destination, returning the
    /// number of code units written. Assumes that source is valid UTF-8
    /// and the destination has sufficient room for the transcoding.
    pub fn toUtf16Be(utf_16: []u16, utf_8: []const u8) usize {
        var i_8: usize = 0;
        var i_16: usize = 0;
        return xtf8AssumeValidToXtf16(false, u8dfa, c_mask, utf_16, utf_8, &i_16, &i_8);
    }

    /// Transcode UTF-8 source into UTF-16LE destination.
    /// Assumes that source is valid UTF-8 and the destination has
    /// sufficient room for the transcoding.
    pub fn toUtf16LeCursor(utf_16: []u16, utf_8: []const u8, i_16: *usize, i_8: *usize) void {
        _ = xtf8AssumeValidToXtf16(true, u8dfa, c_mask, utf_16, utf_8, i_16, i_8);
    }

    /// Transcode UTF-8 source into UTF-16BE destination.
    /// Assumes that source is valid UTF-8 and the destination has
    /// sufficient room for the transcoding.
    pub fn toUtf16BeCursor(utf_16: []u16, utf_8: []const u8, i_16: *usize, i_8: *usize) void {
        _ = xtf8AssumeValidToXtf16(false, u8dfa, c_mask, utf_16, utf_8, i_16, i_8);
    }
};

const wtf8_assume_valid = struct {
    /// Decode the codepoint at `slice[0]`.
    /// Assumes that `slice` begins with a valid WTF-8 codepoint.
    pub fn decode(slice: []const u8) u21 {
        var cursor: usize = 0;
        return decodeCursor(slice, &cursor);
    }

    /// Decode the codepoint at `slice[cursor.*]`.
    /// Assumes that `cursor` points at a valid WTF-8 codepoint.
    pub fn decodeCursor(slice: []const u8, cursor: *usize) u21 {
        return decodeAnyXtf8AssumeValidCursor(w8dfa, c_mask, slice, cursor);
    }

    /// Return whether `slice` is valid WTF-8.
    pub fn validate(slice: []const u8) bool {
        return validateWtf8(slice);
    }

    /// Return whether `slice` is valid WTF-8.
    /// On success, `cursor` is advanced to `slice.len`. On failure,
    /// it points to the first rejected byte.
    pub fn validateCursor(slice: []const u8, cursor: *usize) bool {
        return validateWtf8Cursor(slice, cursor);
    }

    /// Count the number of WTF-8 codepoints in `slice`.
    /// Assumes that `slice` is already valid WTF-8.
    pub fn countCodepoints(slice: []const u8) usize {
        return countCodepointsAssumeValid(slice);
    }

    /// Transcode WTF-8 source into WTF-16LE destination, returning the
    /// number of code units written. Assumes that source is valid WTF-8
    /// and the destination has sufficient room for the transcoding.
    pub fn toWtf16Le(wtf_16: []u16, wtf_8: []const u8) usize {
        var i_8: usize = 0;
        var i_16: usize = 0;
        return xtf8AssumeValidToXtf16(true, w8dfa, c_mask, wtf_16, wtf_8, &i_16, &i_8);
    }

    /// Transcode WTF-8 source into WTF-16BE destination, returning the
    /// number of code units written. Assumes that source is valid WTF-8
    /// and the destination has sufficient room for the transcoding.
    pub fn toWtf16Be(wtf_16: []u16, wtf_8: []const u8) usize {
        var i_8: usize = 0;
        var i_16: usize = 0;
        return xtf8AssumeValidToXtf16(false, w8dfa, c_mask, wtf_16, wtf_8, &i_16, &i_8);
    }

    /// Transcode WTF-8 source into WTF-16LE destination.
    /// Assumes that source is valid WTF-8 and the destination has
    /// sufficient room for the transcoding.
    pub fn toWtf16LeCursor(wtf_16: []u16, wtf_8: []const u8, i_16: *usize, i_8: *usize) void {
        _ = xtf8AssumeValidToXtf16(true, w8dfa, c_mask, wtf_16, wtf_8, i_16, i_8);
    }

    /// Transcode WTF-8 source into WTF-16BE destination.
    /// Assumes that source is valid WTF-8 and the destination has
    /// sufficient room for the transcoding.
    pub fn toWtf16BeCursor(wtf_16: []u16, wtf_8: []const u8, i_16: *usize, i_8: *usize) void {
        _ = xtf8AssumeValidToXtf16(false, w8dfa, c_mask, wtf_16, wtf_8, i_16, i_8);
    }
};

fn Xf8View(comptime xf8_kind: Xf8Kind) fn (comptime ErrorStrategyKind) type {
    return struct {
        fn specialize(comptime strategy: ErrorStrategyKind) type {
            return Xf8ViewImpl(xf8_kind, strategy);
        }
    }.specialize;
}

fn Xf8ViewImpl(comptime xf8_kind: Xf8Kind, comptime strategy: ErrorStrategyKind) type {
    const byte_dfa = switch (xf8_kind) {
        .utf8 => u8dfa,
        .wtf8 => w8dfa,
    };
    const invalid_error = switch (xf8_kind) {
        .utf8 => error.InvalidUtf8,
        .wtf8 => error.InvalidWtf8,
    };

    return struct {
        bytes: []const u8,

        /// Wrap a byte slice as a view without validating it.
        pub fn init(slice: []const u8) @This() {
            return .{ .bytes = slice };
        }

        pub fn Iterator() type {
            return switch (strategy) {
                .exact => ExactCpIteratorImpl(byte_dfa, invalid_error),
                .lossy => LossyCpIteratorImpl(byte_dfa),
                .assume_valid => AssumeValidCpIteratorImpl(byte_dfa, c_mask),
            };
        }

        /// Create an iterator specialized for the selected error strategy.
        pub fn iterator(view: @This()) Iterator() {
            return .{ .bytes = view.bytes };
        }
    };
}

// NOTE: We'll expose this later
//
/// Count codepoints in a slice that is already known to be valid UTF-8 or WTF-8.
fn countCodepointsAssumeValid(slice: []const u8) usize {
    return countValidXtf8(slice);
}

/// Decode the codepoint at `slice[0]`.  Assumes that `slice.len > 0`.
fn decodeXtf8(slice: []const u8) !u21 {
    var cursor: usize = 0;
    return decodeXtf8Cursor(slice, &cursor);
}

/// Decode the codepoint at `slice[0]`. Assumes that `slice` begins with
/// a valid UTF-8 codepoint and that any multibyte sequence is not truncated.
fn decodeXtf8AssumeValid(slice: []const u8) u21 {
    var cursor: usize = 0;
    return decodeAnyXtf8AssumeValidCursor(u8dfa, c_mask, slice, &cursor);
}

/// Decode the codepoint at `slice[cursor.*]`.  The cursor will be advanced to
/// one index past the decoded codepoint, which may include `slice.len`.  If
/// an error is thrown the cursor will point to the first invalid byte
/// in the sequence.  Asserts that `slice` is indexable at `cursor.*`.
fn decodeXtf8Cursor(slice: []const u8, cursor: *usize) !u21 {
    return decodeAnyXtf8Cursor(u8dfa, st_dfa, c_mask, slice, cursor);
}

fn decodeAnyXtf8Cursor(
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
    var cp: u32 = byte & class_mask[class];
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
    cp = (byte & 0x3f) | (cp << 6);
    if (st == UTF_REJECT) return error.InvalidUtf8;
    i.* += 1;
    if (st == UTF_ACCEPT) return @intCast(cp);
    // Byte 3
    byte = slice[i.*];
    class = @intCast(u8dfa[byte]);
    st = state_dfa[st + class];
    cp = (byte & 0x3f) | (cp << 6);
    if (st == UTF_REJECT) return error.InvalidUtf8;
    i.* += 1;
    if (st == UTF_ACCEPT) return @intCast(cp);
    // Byte 4
    byte = slice[i.*];
    class = @intCast(u8dfa[byte]);
    st = state_dfa[st + class];
    cp = (byte & 0x3f) | (cp << 6);
    if (st != UTF_ACCEPT) return error.InvalidUtf8;
    i.* += 1;
    return @intCast(cp);
}

fn decodeAnyXtf8AssumeValidCursor(
    cu_dfa: anytype,
    class_mask: anytype,
    slice: []const u8,
    i: *usize,
) u21 {
    // NOTE: I think the ASCII check is still an optimization
    // here, but we should test that assumption.
    var byte: u16 = slice[i.*];
    i.* += 1;
    if (byte < 0x80) return byte;
    var class: u4 = @intCast(cu_dfa[byte]);
    var st: u32 = st_dfa[class];
    var cp: u32 = byte & class_mask[class];
    byte = slice[i.*];
    class = @intCast(cu_dfa[byte]);
    st = st_dfa[st + class];
    cp = (byte & 0x3f) | (cp << 6);
    i.* += 1;
    if (st == UTF_ACCEPT) {
        return @intCast(cp);
    }
    byte = slice[i.*];
    class = @intCast(cu_dfa[byte]);
    st = st_dfa[st + class];
    cp = (byte & 0x3f) | (cp << 6);
    i.* += 1;
    if (st == UTF_ACCEPT) {
        return @intCast(cp);
    }
    byte = slice[i.*];
    cp = (byte & 0x3f) | (cp << 6);
    i.* += 1;
    return @intCast(cp);
}

fn decodeAnyLossyXtf8Cursor(
    cu_dfa: anytype,
    state_dfa: anytype,
    class_mask: anytype,
    slice: []const u8,
    cursor: *usize,
) u21 {
    assert(cursor.* < slice.len);

    const this_off = cursor.*;
    cursor.* += 1;

    var byte = slice[this_off];
    if (byte < 0x80) return byte;

    var class: u4 = @intCast(cu_dfa[byte]);
    var st: u32 = state_dfa[class];
    if (st == UTF_REJECT or cursor.* == slice.len) {
        @branchHint(.cold);
        return 0xfffd;
    }
    var cp: u32 = byte & class_mask[class];
    byte = slice[cursor.*];
    class = @intCast(cu_dfa[byte]);
    st = state_dfa[st + class];
    cp = (byte & 0x3f) | (cp << 6);
    cursor.* += 1;
    if (st == UTF_ACCEPT) {
        return @intCast(cp);
    }
    if (st == UTF_REJECT or cursor.* == slice.len) {
        @branchHint(.cold);
        cursor.* -= 1;
        return 0xfffd;
    }

    byte = slice[cursor.*];
    class = @intCast(cu_dfa[byte]);
    st = state_dfa[st + class];
    cp = (byte & 0x3f) | (cp << 6);
    cursor.* += 1;
    if (st == UTF_ACCEPT) {
        return @intCast(cp);
    }
    if (st == UTF_REJECT or cursor.* == slice.len) {
        @branchHint(.cold);
        if (state_dfa[@intCast(cu_dfa[byte])] == UTF_REJECT) {
            cursor.* -= 2;
            return 0xfffd;
        } else {
            cursor.* -= 1;
            return 0xfffd;
        }
    }

    byte = slice[cursor.*];
    class = @intCast(cu_dfa[byte]);
    st = state_dfa[st + class];
    cp = (byte & 0x3f) | (cp << 6);
    cursor.* += 1;
    if (st == UTF_REJECT) {
        @branchHint(.cold);
        if (state_dfa[@intCast(cu_dfa[byte])] == UTF_REJECT) {
            cursor.* -= 3;
            return 0xfffd;
        } else {
            cursor.* -= 1;
            return 0xfffd;
        }
    }
    assert(st == UTF_ACCEPT);
    return @intCast(cp);
}

fn ExactCpIteratorImpl(comptime cu_dfa: anytype, comptime invalid_error: anytype) type {
    return struct {
        bytes: []const u8,
        i: usize = 0,

        /// Return the next codepoint, or `null` at end of input.
        pub fn nextCodepoint(iter: *@This()) @TypeOf(invalid_error)!?u21 {
            if (iter.i >= iter.bytes.len) return null;
            return decodeAnyXtf8Cursor(cu_dfa, st_dfa, c_mask, iter.bytes, &iter.i) catch {
                return invalid_error;
            };
        }

        /// Return the byte slice for the next codepoint, or `null` at end of input.
        pub fn nextCodepointSlice(iter: *@This()) @TypeOf(invalid_error)!?[]const u8 {
            if (iter.i >= iter.bytes.len) return null;
            const start = iter.i;
            _ = decodeAnyXtf8Cursor(cu_dfa, st_dfa, c_mask, iter.bytes, &iter.i) catch {
                return invalid_error;
            };
            return iter.bytes[start..iter.i];
        }

        /// Look ahead at the next `n` codepoints without advancing the iterator.
        /// If fewer than `n` codepoints remain, return the remainder of the slice.
        pub fn peek(iter: *@This(), n: usize) @TypeOf(invalid_error)![]const u8 {
            var remaining = n;
            var i = iter.i;
            while (remaining > 0 and i < iter.bytes.len) : (remaining -= 1) {
                _ = decodeAnyXtf8Cursor(cu_dfa, st_dfa, c_mask, iter.bytes, &i) catch {
                    return invalid_error;
                };
            }
            return iter.bytes[iter.i..i];
        }
    };
}

fn LossyCpIteratorImpl(comptime cu_dfa: anytype) type {
    return struct {
        bytes: []const u8,
        i: usize = 0,

        /// Return the next codepoint, substituting U+FFFD for malformed input.
        pub fn nextCodepoint(iter: *@This()) ?u21 {
            if (iter.i >= iter.bytes.len) return null;
            return decodeAnyLossyXtf8Cursor(cu_dfa, st_dfa, c_mask, iter.bytes, &iter.i);
        }

        /// Return the byte slice consumed for the next codepoint or maximal subpart.
        pub fn nextCodepointSlice(iter: *@This()) ?[]const u8 {
            if (iter.i >= iter.bytes.len) return null;
            const start = iter.i;
            _ = decodeAnyLossyXtf8Cursor(cu_dfa, st_dfa, c_mask, iter.bytes, &iter.i);
            return iter.bytes[start..iter.i];
        }

        /// Look ahead at the next `n` codepoints without advancing the iterator.
        pub fn peek(iter: *@This(), n: usize) []const u8 {
            var remaining = n;
            var i = iter.i;
            while (remaining > 0 and i < iter.bytes.len) : (remaining -= 1) {
                _ = decodeAnyLossyXtf8Cursor(cu_dfa, st_dfa, c_mask, iter.bytes, &i);
            }
            return iter.bytes[iter.i..i];
        }
    };
}

fn AssumeValidCpIteratorImpl(comptime cu_dfa: anytype, comptime class_mask: anytype) type {
    return struct {
        bytes: []const u8,
        i: usize = 0,

        /// Return the next codepoint, assuming the remaining input is valid.
        pub fn nextCodepoint(iter: *@This()) ?u21 {
            if (iter.i >= iter.bytes.len) return null;
            return decodeAnyXtf8AssumeValidCursor(cu_dfa, class_mask, iter.bytes, &iter.i);
        }

        /// Return the byte slice for the next codepoint, assuming the
        /// remaining input is valid.
        pub fn nextCodepointSlice(iter: *@This()) ?[]const u8 {
            if (iter.i >= iter.bytes.len) return null;
            const start = iter.i;
            iter.i += xtf8CpLengthAssumeValid(iter.bytes[iter.i]);
            return iter.bytes[start..iter.i];
        }

        /// Look ahead at the next `n` codepoints without advancing the iterator.
        pub fn peek(iter: *@This(), n: usize) []const u8 {
            var remaining = n;
            var i = iter.i;
            while (remaining > 0 and i < iter.bytes.len) : (remaining -= 1) {
                i += xtf8CpLengthAssumeValid(iter.bytes[i]);
            }
            return iter.bytes[iter.i..i];
        }
    };
}

fn xtf8CpLengthAssumeValid(byte: u8) usize {
    return switch (byte) {
        0...0x7f => 1,
        0xc2...0xdf => 2,
        0xe0...0xef => 3,
        0xf0...0xf4 => 4,
        else => unreachable,
    };
}

fn countAnyLossyCps(cu_dfa: anytype, slice: []const u8) usize {
    var cursor: usize = 0;
    var count: usize = 0;
    while (cursor < slice.len) {
        _ = decodeAnyLossyXtf8Cursor(cu_dfa, st_dfa, c_mask, slice, &cursor);
        count += 1;
    }
    return count;
}

fn countXtf8(slice: []const u8) !usize {
    return countAnyXtf8(u8dfa, st_dfa, slice);
}

fn countWtf8(slice: []const u8) !usize {
    return countAnyXtf8(w8dfa, st_dfa, slice);
}

fn countAnyXtf8(cu_dfa: anytype, state_dfa: anytype, slice: []const u8) !usize {
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

/// Count the number of codepoints in an assumed-valid slice.  This gives correct
/// answers for either of WTF-8 or UTF-8, provided that the string is valid by
/// either standard.  Invalid data will give a spurious answer, but is otherwise
/// safe to provide.
fn countValidXtf8(slice: []const u8) usize {
    var c: usize = 0;
    for (slice) |b| {
        c += weight[b >> 6];
    }
    return c;
}

/// Validate that a slice is composed only of valid codepoints in the
/// UTF-8 encoding.
fn validateXtf8(slice: []const u8) bool {
    var i: usize = 0;
    return validateAnyXtf8WithCursor(u8dfa, st_dfa, slice, &i);
}

/// Validate that a slice is composed only of valid codepoints in the
/// WTF-8 encoding.
fn validateWtf8(slice: []const u8) bool {
    var i: usize = 0;
    return validateAnyXtf8WithCursor(w8dfa, st_dfa, slice, &i);
}

/// UTF-8 encoding.  Must be passed a cursor, by pointer: this
/// will point to slice.len when the return value is `true`, and
/// to the first rejected byte when `false`.
fn validateXtf8Cursor(slice: []const u8, i: *usize) bool {
    return validateAnyXtf8WithCursor(u8dfa, st_dfa, slice, i);
}

/// Validate that a slice is composed only of valid runes in the
/// WTF-8 encoding.  Must be passed a cursor, by pointer: this
/// will point to slice.len when the return value is `true`, and
/// to the first rejected byte when `false`.
fn validateWtf8Cursor(slice: []const u8, i: *usize) bool {
    return validateAnyXtf8WithCursor(w8dfa, st_dfa, slice, i);
}

fn validateAnyXtf8WithCursor(
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

/// Transcode utf_8 source into utf_16 destination, returning the
/// length of a slice of utf_16 containing the transcoded points.
/// Assumes that the destination has sufficient room for the transcoding.
fn utf8ToUtf16Le(utf_16: []u16, utf_8: []const u8) !usize {
    var i_8: usize = 0;
    var i_16: usize = 0;
    return xtf8ToXtf16(true, u8dfa, st_dfa, c_mask, utf_16, utf_8, &i_16, &i_8);
}

/// Transcode utf_8 source into utf_16 destination, returning the
/// length of a slice of utf_16 containing the transcoded points.
/// Assumes that the destination has sufficient room for the transcoding.
fn utf8ToUtf16Be(utf_16: []u16, utf_8: []const u8) !usize {
    var i_8: usize = 0;
    var i_16: usize = 0;
    return xtf8ToXtf16(false, u8dfa, st_dfa, c_mask, utf_16, utf_8, &i_16, &i_8);
}

/// Transcode utf_8 source into utf_16 destination Assumes that the
/// destination has sufficient room for the transcoding.
/// Takes two cursors: if an error is thrown, the i_16 cursor points to
/// the index past the last transcoded point, and the i_8 cursor points to
/// the source of the error.  Success means that i_16 points to the point
/// in utf_16 which may be sliced to obtain the result.
fn utf8ToUtf16LeCursor(
    utf_16: []u16,
    utf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) !void {
    _ = try xtf8ToXtf16(true, u8dfa, st_dfa, c_mask, utf_16, utf_8, i_16, i_8);
}

/// Transcode utf_8 source into utf_16 destination Assumes that the
/// destination has sufficient room for the transcoding.
/// Takes two cursors: if an error is thrown, the i_16 cursor points to
/// the index past the last transcoded point, and the i_8 cursor points to
/// the source of the error.  Success means that i_16 points to the point
/// in utf_16 which may be sliced to obtain the result.
fn utf8ToUtf16BeCursor(
    utf_16: []u16,
    utf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) !void {
    _ = try xtf8ToXtf16(false, u8dfa, st_dfa, c_mask, utf_16, utf_8, i_16, i_8);
}

/// Transcode wtf_8 source into wtf_16 destination, returning the
/// length of a slice of wtf_16 containing the transcoded points.
/// Assumes that the destination has sufficient room for the transcoding.
fn wtf8ToWtf16Le(wtf_16: []u16, wtf_8: []const u8) !usize {
    var i_8: usize = 0;
    var i_16: usize = 0;
    return xtf8ToXtf16(true, w8dfa, st_dfa, c_mask, wtf_16, wtf_8, &i_16, &i_8);
}

/// Transcode wtf_8 source into wtf_16 destination, returning the
/// length of a slice of wtf_16 containing the transcoded points.
/// Assumes that the destination has sufficient room for the transcoding.
fn wtf8ToWtf16Be(wtf_16: []u16, wtf_8: []const u8) !usize {
    var i_8: usize = 0;
    var i_16: usize = 0;
    return xtf8ToXtf16(false, w8dfa, st_dfa, c_mask, wtf_16, wtf_8, &i_16, &i_8);
}

/// Transcode wtf_8 source into wtf_16 destination.  Assumes that the
/// destination has sufficient room for the transcoding.
/// Takes two cursors: if an error is thrown, the i_16 cursor points to
/// the index past the last transcoded point, and the i_8 cursor points to
/// the source of the error.  Success means that i_16 points to the point
/// in wtf_16 which may be sliced to obtain the result.
fn wtf8ToWtf16LeCursor(
    wtf_16: []u16,
    wtf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) !void {
    _ = try xtf8ToXtf16(true, w8dfa, st_dfa, c_mask, wtf_16, wtf_8, i_16, i_8);
}

/// Transcode wtf_8 source into wtf_16 destination.  Assumes that the
/// destination has sufficient room for the transcoding.
/// Takes two cursors: if an error is thrown, the i_16 cursor points to
/// the index past the last transcoded point, and the i_8 cursor points to
/// the source of the error.  Success means that i_16 points to the point
/// in wtf_16 which may be sliced to obtain the result.
fn wtf8ToWtf16BeCursor(
    wtf_16: []u16,
    wtf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) !void {
    _ = try xtf8ToXtf16(false, w8dfa, st_dfa, c_mask, wtf_16, wtf_8, i_16, i_8);
}

fn xtf8ToXtf16(
    comptime little_endian: bool,
    cu_dfa: anytype,
    state_dfa: anytype,
    class_mask: anytype,
    utf_16: []u16,
    utf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) !usize {
    const nativeToEndian = if (little_endian)
        std.mem.nativeToLittle
    else
        std.mem.nativeToBig;
    var st: u32 = 0;
    var cp: u32 = 0;
    while (i_8.* < utf_8.len) : (i_8.* += 1) {
        const b = utf_8[i_8.*];
        if (st == UTF_ACCEPT) {
            if (b < 0x80) {
                utf_16[i_16.*] = nativeToEndian(u16, b);
                i_16.* += 1;
            } else {
                const class = cu_dfa[b];
                st = state_dfa[class];
                cp = b & class_mask[class];
            }
            continue;
        }
        st = state_dfa[st + cu_dfa[b]];
        cp = (b & 0x3f) | (cp << 6);
        if (st == UTF_REJECT) {
            @branchHint(.cold);
            return error.InvalidUtf8;
        } else if (st == UTF_ACCEPT) {
            if (cp < 0x10000) {
                utf_16[i_16.*] = nativeToEndian(u16, @intCast(cp));
                i_16.* += 1;
            } else {
                const high = @as(u16, @intCast((cp - 0x10000) >> 10)) + 0xD800;
                const low = @as(u16, @intCast(cp & 0x3FF)) + 0xDC00;
                utf_16[i_16.*] = nativeToEndian(u16, high);
                i_16.* += 1;
                utf_16[i_16.*] = nativeToEndian(u16, low);
                i_16.* += 1;
            }
        }
    }
    return i_16.*;
}

fn xtf8LossyToXtf16(
    comptime little_endian: bool,
    cu_dfa: anytype,
    state_dfa: anytype,
    class_mask: anytype,
    utf_16: []u16,
    utf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) usize {
    _ = state_dfa;
    _ = class_mask;
    const nativeToEndian = if (little_endian)
        std.mem.nativeToLittle
    else
        std.mem.nativeToBig;

    while (i_8.* < utf_8.len) {
        const cp = decodeAnyLossyXtf8Cursor(cu_dfa, st_dfa, c_mask, utf_8, i_8);
        if (cp < 0x10000) {
            utf_16[i_16.*] = nativeToEndian(u16, @intCast(cp));
            i_16.* += 1;
        } else {
            const high = @as(u16, @intCast((cp - 0x10000) >> 10)) + 0xD800;
            const low = @as(u16, @intCast(cp & 0x3FF)) + 0xDC00;
            utf_16[i_16.*] = nativeToEndian(u16, high);
            i_16.* += 1;
            utf_16[i_16.*] = nativeToEndian(u16, low);
            i_16.* += 1;
        }
    }
    return i_16.*;
}

fn xtf8AssumeValidToXtf16(
    comptime little_endian: bool,
    cu_dfa: anytype,
    class_mask: anytype,
    utf_16: []u16,
    utf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) usize {
    const nativeToEndian = if (little_endian)
        std.mem.nativeToLittle
    else
        std.mem.nativeToBig;

    while (i_8.* < utf_8.len) {
        const cp = decodeAnyXtf8AssumeValidCursor(cu_dfa, class_mask, utf_8, i_8);
        if (cp < 0x10000) {
            utf_16[i_16.*] = nativeToEndian(u16, @intCast(cp));
            i_16.* += 1;
        } else {
            const high = @as(u16, @intCast((cp - 0x10000) >> 10)) + 0xD800;
            const low = @as(u16, @intCast(cp & 0x3FF)) + 0xDC00;
            utf_16[i_16.*] = nativeToEndian(u16, high);
            i_16.* += 1;
            utf_16[i_16.*] = nativeToEndian(u16, low);
            i_16.* += 1;
        }
    }
    return i_16.*;
}

fn expectBigEndianUtf16(expected_native: []const u16, actual_big_endian: []const u16) !void {
    try testing.expectEqual(expected_native.len, actual_big_endian.len);
    for (expected_native, actual_big_endian) |expected, actual| {
        try testing.expectEqual(std.mem.nativeToBig(u16, expected), actual);
    }
}

const ascii = "abcde";
const greek = "αβγδε";
const mixed = "aβ∅🤓";
const maths = "∅⊄⊅⊆⊇";
const emotes = "🤓😎🥸🤩🤯";
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

test "utf8.validate and countCodepoints accept valid input" {
    try testing.expect(utf8.validate(ascii));
    try testing.expect(utf8.validate(greek));
    try testing.expect(utf8.validate(mixed));

    try testing.expectEqual(@as(usize, 5), try utf8.countCodepoints(ascii));
    try testing.expectEqual(@as(usize, 5), try utf8.countCodepoints(greek));
    try testing.expectEqual(@as(usize, 4), try utf8.countCodepoints(mixed));
}

test "utf8 invalid data reports the first bad byte" {
    const invalid = "a\xf0\x28\x8c\xbc";

    var validate_cursor: usize = 0;
    try testing.expect(!utf8.validateCursor(invalid, &validate_cursor));
    try testing.expectEqual(@as(usize, 2), validate_cursor);

    var decode_cursor: usize = 1;
    try testing.expectError(error.InvalidUtf8, utf8.decodeCursor(invalid, &decode_cursor));
    try testing.expectEqual(@as(usize, 2), decode_cursor);
}

test "utf8 rejects truncated sequences" {
    const truncated = "\xf0\x9f\x92";

    try testing.expect(!utf8.validate(truncated));
    try testing.expectError(error.InvalidUtf8, utf8.countCodepoints(truncated));

    var cursor: usize = 0;
    try testing.expectError(error.InvalidUtf8, utf8.decodeCursor(truncated, &cursor));
    try testing.expectEqual(@as(usize, 1), cursor);
}

test "wtf8 namespace matches shared valid utf8 behavior" {
    try testing.expect(wtf8.validate(greek));
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

    try testing.expect(!wtf8.validate(invalid));
    try testing.expectError(error.InvalidWtf8, wtf8.countCodepoints(invalid));

    var cursor: usize = 0;
    try testing.expectError(error.InvalidWtf8, wtf8.decodeCursor(invalid, &cursor));
}

test "utf8.assume_valid matches exact behavior on valid input" {
    try testing.expectEqual(try utf8.decode("α"), utf8.valid.decode("α"));

    var exact_cursor: usize = 0;
    var assume_cursor: usize = 0;
    try testing.expectEqual(try utf8.decodeCursor(mixed, &exact_cursor), utf8.valid.decodeCursor(mixed, &assume_cursor));
    try testing.expectEqual(exact_cursor, assume_cursor);

    try testing.expectEqual(try utf8.countCodepoints(mixed), utf8.valid.countCodepoints(mixed));

    var out_exact_le: [10]u16 = undefined;
    var out_assume_le: [10]u16 = undefined;
    const exact_le_len = try utf8.toUtf16Le(&out_exact_le, emotes);
    const assume_le_len = utf8.valid.toUtf16Le(&out_assume_le, emotes);
    try testing.expectEqual(exact_le_len, assume_le_len);
    try testing.expectEqualSlices(u16, out_exact_le[0..exact_le_len], out_assume_le[0..assume_le_len]);

    var out_exact_be: [10]u16 = undefined;
    var out_assume_be: [10]u16 = undefined;
    const exact_be_len = try utf8.toUtf16Be(&out_exact_be, emotes);
    const assume_be_len = utf8.valid.toUtf16Be(&out_assume_be, emotes);
    try testing.expectEqual(exact_be_len, assume_be_len);
    try testing.expectEqualSlices(u16, out_exact_be[0..exact_be_len], out_assume_be[0..assume_be_len]);

    var exact_i_16: usize = 0;
    var exact_i_8: usize = 0;
    var assume_i_16: usize = 0;
    var assume_i_8: usize = 0;
    try utf8.toUtf16LeCursor(&out_exact_le, mixed, &exact_i_16, &exact_i_8);
    utf8.valid.toUtf16LeCursor(&out_assume_le, mixed, &assume_i_16, &assume_i_8);
    try testing.expectEqual(exact_i_16, assume_i_16);
    try testing.expectEqual(exact_i_8, assume_i_8);
    try testing.expectEqualSlices(u16, out_exact_le[0..exact_i_16], out_assume_le[0..assume_i_16]);
}

test "wtf8.assume_valid matches exact behavior on valid input" {
    try testing.expectEqual(try wtf8.decode("α"), wtf8.valid.decode("α"));

    var exact_cursor: usize = 0;
    var assume_cursor: usize = 0;
    try testing.expectEqual(try wtf8.decodeCursor(mixed, &exact_cursor), wtf8.valid.decodeCursor(mixed, &assume_cursor));
    try testing.expectEqual(exact_cursor, assume_cursor);

    try testing.expectEqual(try wtf8.countCodepoints(mixed), wtf8.valid.countCodepoints(mixed));

    var out_exact_le: [10]u16 = undefined;
    var out_assume_le: [10]u16 = undefined;
    const exact_le_len = try wtf8.toWtf16Le(&out_exact_le, emotes);
    const assume_le_len = wtf8.valid.toWtf16Le(&out_assume_le, emotes);
    try testing.expectEqual(exact_le_len, assume_le_len);
    try testing.expectEqualSlices(u16, out_exact_le[0..exact_le_len], out_assume_le[0..assume_le_len]);

    var out_exact_be: [10]u16 = undefined;
    var out_assume_be: [10]u16 = undefined;
    const exact_be_len = try wtf8.toWtf16Be(&out_exact_be, emotes);
    const assume_be_len = wtf8.valid.toWtf16Be(&out_assume_be, emotes);
    try testing.expectEqual(exact_be_len, assume_be_len);
    try testing.expectEqualSlices(u16, out_exact_be[0..exact_be_len], out_assume_be[0..assume_be_len]);

    var exact_i_16: usize = 0;
    var exact_i_8: usize = 0;
    var assume_i_16: usize = 0;
    var assume_i_8: usize = 0;
    try wtf8.toWtf16LeCursor(&out_exact_le, mixed, &exact_i_16, &exact_i_8);
    wtf8.valid.toWtf16LeCursor(&out_assume_le, mixed, &assume_i_16, &assume_i_8);
    try testing.expectEqual(exact_i_16, assume_i_16);
    try testing.expectEqual(exact_i_8, assume_i_8);
    try testing.expectEqualSlices(u16, out_exact_le[0..exact_i_16], out_assume_le[0..assume_i_16]);
}

test "utf8.toUtf16Le matches std.unicode" {
    var out_std: [10]u16 = undefined;
    var out_unicode: [10]u16 = undefined;
    {
        _ = try std.unicode.utf8ToUtf16Le(&out_std, greek);
        const count = try utf8.toUtf16Le(&out_unicode, greek);
        try testing.expectEqual(@as(usize, 5), count);
        try testing.expectEqualSlices(u16, out_std[0..5], out_unicode[0..5]);
    }
    {
        _ = try std.unicode.utf8ToUtf16Le(&out_std, maths);
        const count = try utf8.toUtf16Le(&out_unicode, maths);
        try testing.expectEqual(@as(usize, 5), count);
        try testing.expectEqualSlices(u16, out_std[0..5], out_unicode[0..5]);
    }
    {
        _ = try std.unicode.utf8ToUtf16Le(&out_std, emotes);
        const count = try utf8.toUtf16Le(&out_unicode, emotes);
        try testing.expectEqual(@as(usize, 10), count);
        try testing.expectEqualSlices(u16, &out_std, &out_unicode);
    }
}

test "utf8.toUtf16Be matches std.unicode with big-endian words" {
    var out_std: [10]u16 = undefined;
    var out_unicode: [10]u16 = undefined;
    {
        _ = try std.unicode.utf8ToUtf16Le(&out_std, greek);
        const count = try utf8.toUtf16Be(&out_unicode, greek);
        try testing.expectEqual(@as(usize, 5), count);
        try expectBigEndianUtf16(out_std[0..5], out_unicode[0..5]);
    }
    {
        _ = try std.unicode.utf8ToUtf16Le(&out_std, maths);
        const count = try utf8.toUtf16Be(&out_unicode, maths);
        try testing.expectEqual(@as(usize, 5), count);
        try expectBigEndianUtf16(out_std[0..5], out_unicode[0..5]);
    }
    {
        _ = try std.unicode.utf8ToUtf16Le(&out_std, emotes);
        const count = try utf8.toUtf16Be(&out_unicode, emotes);
        try testing.expectEqual(@as(usize, 10), count);
        try expectBigEndianUtf16(&out_std, &out_unicode);
    }
}

test "utf8.toUtf16LeCursor advances source and destination cursors" {
    var out: [10]u16 = undefined;
    var i_16: usize = 0;
    var i_8: usize = 0;

    try utf8.toUtf16LeCursor(&out, mixed, &i_16, &i_8);
    try testing.expectEqual(@as(usize, 5), i_16);
    try testing.expectEqual(mixed.len, i_8);
}

test "utf8.toUtf16BeCursor advances source and destination cursors" {
    var out: [10]u16 = undefined;
    var i_16: usize = 0;
    var i_8: usize = 0;

    try utf8.toUtf16BeCursor(&out, mixed, &i_16, &i_8);
    try testing.expectEqual(@as(usize, 5), i_16);
    try testing.expectEqual(mixed.len, i_8);
}

test "utf8.toUtf16LeCursor preserves partial progress on malformed input" {
    const invalid = "a\xf0\x28\x8c\xbc";
    var out: [10]u16 = undefined;
    var i_16: usize = 0;
    var i_8: usize = 0;

    try testing.expectError(error.InvalidUtf8, utf8.toUtf16LeCursor(&out, invalid, &i_16, &i_8));
    try testing.expectEqual(@as(usize, 1), i_16);
    try testing.expectEqual(@as(usize, 2), i_8);
}

test "wtf8 transcoding wrappers remap malformed input to InvalidWtf8" {
    const invalid = "\xf0\x28\x8c\xbc";
    var out: [10]u16 = undefined;
    var i_16: usize = 0;
    var i_8: usize = 0;

    try testing.expectError(error.InvalidWtf8, wtf8.toWtf16Le(&out, invalid));
    try testing.expectError(error.InvalidWtf8, wtf8.toWtf16LeCursor(&out, invalid, &i_16, &i_8));
    try testing.expectEqual(@as(usize, 0), i_16);
    try testing.expectEqual(@as(usize, 1), i_8);
}

fn testUtf8ViewNextCp(slice: []const u8) !void {
    const view = utf8.iterator(slice, .exact);
    var iter = view.iterator();
    var cursor: usize = 0;
    while (try iter.nextCodepoint()) |cp| {
        const expected = try utf8.decodeCursor(slice, &cursor);
        try testing.expectEqual(expected, cp);
    }
    try testing.expectEqual(slice.len, cursor);
}

fn testUtf8ViewNextCpSlice(slice: []const u8) !void {
    const view = utf8.Utf8View(.exact).init(slice);
    var iter = view.iterator();
    var cursor: usize = 0;
    while (try iter.nextCodepointSlice()) |cp_slice| {
        const start = cursor;
        _ = try utf8.decodeCursor(slice, &cursor);
        try testing.expectEqualStrings(slice[start..cursor], cp_slice);
    }
    try testing.expectEqual(slice.len, cursor);
}

fn testWtf8ViewNextCp(slice: []const u8) !void {
    const view = wtf8.iterator(slice, .exact);
    var iter = view.iterator();
    var cursor: usize = 0;
    while (try iter.nextCodepoint()) |cp| {
        const expected = try wtf8.decodeCursor(slice, &cursor);
        try testing.expectEqual(expected, cp);
    }
    try testing.expectEqual(slice.len, cursor);
}

fn testWtf8ViewNextCpSlice(slice: []const u8) !void {
    const view = wtf8.Wtf8View(.exact).init(slice);
    var iter = view.iterator();
    var cursor: usize = 0;
    while (try iter.nextCodepointSlice()) |cp_slice| {
        const start = cursor;
        _ = try wtf8.decodeCursor(slice, &cursor);
        try testing.expectEqualStrings(slice[start..cursor], cp_slice);
    }
    try testing.expectEqual(slice.len, cursor);
}

fn prefixAfterNCps(slice: []const u8, n: usize) ![]const u8 {
    var cursor: usize = 0;
    var remaining = n;
    while (remaining > 0 and cursor < slice.len) : (remaining -= 1) {
        _ = try utf8.decodeCursor(slice, &cursor);
    }
    return slice[0..cursor];
}

fn prefixAfterNLossyCps(cu_dfa: anytype, slice: []const u8, n: usize) []const u8 {
    var cursor: usize = 0;
    var remaining = n;
    while (remaining > 0 and cursor < slice.len) : (remaining -= 1) {
        _ = decodeAnyLossyXtf8Cursor(cu_dfa, st_dfa, c_mask, slice, &cursor);
    }
    return slice[0..cursor];
}

fn expectUtf8LossyDecode(bytes: []const u8, expected_cps: []const u21, expected_lens: []const usize) !void {
    try testing.expectEqual(expected_cps.len, expected_lens.len);
    var cursor: usize = 0;
    for (expected_cps, expected_lens) |expected_cp, expected_len| {
        const start = cursor;
        try testing.expectEqual(expected_cp, utf8.lossy.decodeCursor(bytes, &cursor));
        try testing.expectEqual(expected_len, cursor - start);
    }
    try testing.expectEqual(bytes.len, cursor);
}

fn expectWtf8LossyDecode(bytes: []const u8, expected_cps: []const u21, expected_lens: []const usize) !void {
    try testing.expectEqual(expected_cps.len, expected_lens.len);
    var cursor: usize = 0;
    for (expected_cps, expected_lens) |expected_cp, expected_len| {
        const start = cursor;
        try testing.expectEqual(expected_cp, wtf8.lossy.decodeCursor(bytes, &cursor));
        try testing.expectEqual(expected_len, cursor - start);
    }
    try testing.expectEqual(bytes.len, cursor);
}

fn expectUtf8LossyIteratorSlices(bytes: []const u8, expected_lens: []const usize) !void {
    const view = utf8.iterator(bytes, .lossy);
    var iter = view.iterator();
    for (expected_lens) |expected_len| {
        const slice = iter.nextCodepointSlice().?;
        try testing.expectEqual(expected_len, slice.len);
    }
    try testing.expectEqual(@as(?[]const u8, null), iter.nextCodepointSlice());
}

fn expectWtf8LossyIteratorSlices(bytes: []const u8, expected_lens: []const usize) !void {
    const view = wtf8.iterator(bytes, .lossy);
    var iter = view.iterator();
    for (expected_lens) |expected_len| {
        const slice = iter.nextCodepointSlice().?;
        try testing.expectEqual(expected_len, slice.len);
    }
    try testing.expectEqual(@as(?[]const u8, null), iter.nextCodepointSlice());
}

test "Utf8View iterator exact nextCodepoint matches decodeCursor" {
    try testUtf8ViewNextCp(ascii);
    try testUtf8ViewNextCp(greek);
    try testUtf8ViewNextCp(maths);
    try testUtf8ViewNextCp(emotes);
}

test "Utf8View iterator exact nextCodepointSlice matches input slices" {
    try testUtf8ViewNextCpSlice(ascii);
    try testUtf8ViewNextCpSlice(greek);
    try testUtf8ViewNextCpSlice(maths);
    try testUtf8ViewNextCpSlice(emotes);
}

test "Utf8View iterator exact peek returns prefix without advancing" {
    const view = utf8.Utf8View(.exact).init(emotes);
    var iter = view.iterator();
    const expected = try prefixAfterNCps(emotes, 3);
    try testing.expectEqualStrings(expected, try iter.peek(3));
    try testing.expectEqual(@as(usize, 0), iter.i);
}

test "Utf8View iterator exact reports end of input" {
    const view = utf8.Utf8View(.exact).init(ascii);
    var iter = view.iterator();
    while (try iter.nextCodepoint()) |_| {}
    try testing.expectEqual(@as(?u21, null), try iter.nextCodepoint());
    try testing.expectEqual(@as(?[]const u8, null), try iter.nextCodepointSlice());
}

test "Utf8View iterator exact reports malformed input" {
    const invalid = "a\xf0\x28\x8c\xbc";
    const truncated = "\xf0\x9f\x92";

    {
        const view = utf8.Utf8View(.exact).init(invalid);
        var iter = view.iterator();
        try testing.expectEqual(@as(u21, 'a'), (try iter.nextCodepoint()).?);
        try testing.expectError(error.InvalidUtf8, iter.nextCodepoint());
    }
    {
        const view = utf8.Utf8View(.exact).init(invalid);
        var iter = view.iterator();
        _ = try iter.nextCodepointSlice();
        try testing.expectError(error.InvalidUtf8, iter.nextCodepointSlice());
    }
    {
        const view = utf8.Utf8View(.exact).init(invalid);
        var iter = view.iterator();
        try testing.expectError(error.InvalidUtf8, iter.peek(3));
        try testing.expectEqual(@as(usize, 0), iter.i);
    }
    {
        const view = utf8.Utf8View(.exact).init(truncated);
        var iter = view.iterator();
        try testing.expectError(error.InvalidUtf8, iter.nextCodepoint());
    }
}

test "Wtf8View iterator exact nextCodepoint matches decodeCursor" {
    try testWtf8ViewNextCp(ascii);
    try testWtf8ViewNextCp(greek);
    try testWtf8ViewNextCp(maths);
    try testWtf8ViewNextCp(emotes);
}

test "Wtf8View iterator exact nextCodepointSlice matches input slices" {
    try testWtf8ViewNextCpSlice(ascii);
    try testWtf8ViewNextCpSlice(greek);
    try testWtf8ViewNextCpSlice(maths);
    try testWtf8ViewNextCpSlice(emotes);
}

test "Wtf8View iterator exact reports malformed input as InvalidWtf8" {
    const invalid = "\xf0\x28\x8c\xbc";
    const view = wtf8.Wtf8View(.exact).init(invalid);

    {
        var iter = view.iterator();
        try testing.expectError(error.InvalidWtf8, iter.nextCodepoint());
    }
    {
        var iter = view.iterator();
        try testing.expectError(error.InvalidWtf8, iter.nextCodepointSlice());
    }
    {
        var iter = view.iterator();
        try testing.expectError(error.InvalidWtf8, iter.peek(1));
        try testing.expectEqual(@as(usize, 0), iter.i);
    }
}

test "utf8.lossy decode preserves valid input" {
    try testing.expectEqual(@as(u21, 'a'), utf8.lossy.decode("abc"));
    try testing.expectEqual(@as(u21, 0x03B1), utf8.lossy.decode("α"));
    try testing.expectEqual(@as(u21, 0x1F913), utf8.lossy.decode("🤓"));
}

test "utf8.lossy overlongs use replacement characters" {
    try expectUtf8LossyDecode("\xc0\xaf", &.{ 0xfffd, 0xfffd }, &.{ 1, 1 });
    try expectUtf8LossyDecode("\xe0\x80\xaf", &.{ 0xfffd, 0xfffd, 0xfffd }, &.{ 1, 1, 1 });
    try expectUtf8LossyDecode("\xf0\x80\x80\xaf", &.{ 0xfffd, 0xfffd, 0xfffd, 0xfffd }, &.{ 1, 1, 1, 1 });
}

test "utf8.lossy surrogate-form sequences use replacement characters" {
    try expectUtf8LossyDecode("\xed\xad\xbf", &.{ 0xfffd, 0xfffd, 0xfffd }, &.{ 1, 1, 1 });
}

test "utf8.lossy truncation follows maximal subparts" {
    const bytes = "\xe1\x80\xe2\xf0\x91\x92\xf1\xbf\x41";
    try expectUtf8LossyDecode(bytes, &.{ 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0x41 }, &.{ 2, 1, 3, 2, 1 });
}

test "utf8.lossy countCodepoints counts replacements" {
    try testing.expectEqual(@as(usize, 4), utf8.lossy.countCodepoints(mixed));
    try testing.expectEqual(@as(usize, 2), utf8.lossy.countCodepoints("\xc0\xaf"));
    try testing.expectEqual(@as(usize, 5), utf8.lossy.countCodepoints("\xe1\x80\xe2\xf0\x91\x92\xf1\xbf\x41"));
}

test "utf8.lossy validate matches exact validation" {
    const invalid = "a\xf0\x28\x8c\xbc";

    try testing.expectEqual(utf8.validate(mixed), utf8.lossy.validate(mixed));
    try testing.expectEqual(utf8.validate(invalid), utf8.lossy.validate(invalid));

    var exact_cursor: usize = 0;
    var lossy_cursor: usize = 0;
    try testing.expectEqual(utf8.validateCursor(invalid, &exact_cursor), utf8.lossy.validateCursor(invalid, &lossy_cursor));
    try testing.expectEqual(exact_cursor, lossy_cursor);
}

test "utf8.lossy transcoding emits replacement characters" {
    const bytes = "\xe1\x80\xe2\xf0\x91\x92\xf1\xbf\x41";
    const expected_native = [_]u16{ 0xfffd, 0xfffd, 0xfffd, 0xfffd, 0x41 };
    var out_le: [expected_native.len]u16 = undefined;
    var out_be: [expected_native.len]u16 = undefined;

    try testing.expectEqual(expected_native.len, utf8.lossy.toUtf16Le(&out_le, bytes));
    try testing.expectEqualSlices(u16, &expected_native, &out_le);
    try testing.expectEqual(expected_native.len, utf8.lossy.toUtf16Be(&out_be, bytes));
    try expectBigEndianUtf16(&expected_native, &out_be);

    var i_16: usize = 0;
    var i_8: usize = 0;
    utf8.lossy.toUtf16LeCursor(&out_le, bytes, &i_16, &i_8);
    try testing.expectEqual(expected_native.len, i_16);
    try testing.expectEqual(bytes.len, i_8);
}

test "Utf8View iterator lossy yields replacements and maximal subpart slices" {
    const bytes = "\xe1\x80\xe2\xf0\x91\x92\xf1\xbf\x41";
    const view = utf8.iterator(bytes, .lossy);
    var iter = view.iterator();

    try testing.expectEqual(@as(u21, 0xfffd), iter.nextCodepoint().?);
    try testing.expectEqual(@as(u21, 0xfffd), iter.nextCodepoint().?);
    try testing.expectEqual(@as(u21, 0xfffd), iter.nextCodepoint().?);
    try testing.expectEqual(@as(u21, 0xfffd), iter.nextCodepoint().?);
    try testing.expectEqual(@as(u21, 0x41), iter.nextCodepoint().?);
    try testing.expectEqual(@as(?u21, null), iter.nextCodepoint());

    try expectUtf8LossyIteratorSlices(bytes, &.{ 2, 1, 3, 2, 1 });

    iter = view.iterator();
    try testing.expectEqualStrings(prefixAfterNLossyCps(u8dfa, bytes, 3), iter.peek(3));
    try testing.expectEqual(@as(usize, 0), iter.i);
}

test "wtf8.lossy preserves valid input and replaces malformed input" {
    try testing.expectEqual(@as(u21, 0x03B1), wtf8.lossy.decode("α"));
    try expectWtf8LossyDecode("\xc0\xaf", &.{ 0xfffd, 0xfffd }, &.{ 1, 1 });
}

test "wtf8.lossy countCodepoints and transcode replace malformed input" {
    const bytes = "\xc0\xaf";
    const expected_native = [_]u16{ 0xfffd, 0xfffd };
    var out_le: [expected_native.len]u16 = undefined;
    var out_be: [expected_native.len]u16 = undefined;

    try testing.expectEqual(@as(usize, 2), wtf8.lossy.countCodepoints(bytes));
    try testing.expectEqual(expected_native.len, wtf8.lossy.toWtf16Le(&out_le, bytes));
    try testing.expectEqualSlices(u16, &expected_native, &out_le);
    try testing.expectEqual(expected_native.len, wtf8.lossy.toWtf16Be(&out_be, bytes));
    try expectBigEndianUtf16(&expected_native, &out_be);

    var i_16: usize = 0;
    var i_8: usize = 0;
    wtf8.lossy.toWtf16LeCursor(&out_le, bytes, &i_16, &i_8);
    try testing.expectEqual(expected_native.len, i_16);
    try testing.expectEqual(bytes.len, i_8);
}

test "wtf8.lossy validate matches exact validation" {
    const invalid = "\xf0\x28\x8c\xbc";

    try testing.expectEqual(wtf8.validate(greek), wtf8.lossy.validate(greek));
    try testing.expectEqual(wtf8.validate(invalid), wtf8.lossy.validate(invalid));

    var exact_cursor: usize = 0;
    var lossy_cursor: usize = 0;
    try testing.expectEqual(wtf8.validateCursor(invalid, &exact_cursor), wtf8.lossy.validateCursor(invalid, &lossy_cursor));
    try testing.expectEqual(exact_cursor, lossy_cursor);
}

test "utf8.assume_valid validate matches exact validation" {
    const invalid = "a\xf0\x28\x8c\xbc";

    try testing.expectEqual(utf8.validate(mixed), utf8.valid.validate(mixed));
    try testing.expectEqual(utf8.validate(invalid), utf8.valid.validate(invalid));

    var exact_cursor: usize = 0;
    var assume_cursor: usize = 0;
    try testing.expectEqual(utf8.validateCursor(invalid, &exact_cursor), utf8.valid.validateCursor(invalid, &assume_cursor));
    try testing.expectEqual(exact_cursor, assume_cursor);
}

test "wtf8.assume_valid validate matches exact validation" {
    const invalid = "\xf0\x28\x8c\xbc";

    try testing.expectEqual(wtf8.validate(greek), wtf8.valid.validate(greek));
    try testing.expectEqual(wtf8.validate(invalid), wtf8.valid.validate(invalid));

    var exact_cursor: usize = 0;
    var assume_cursor: usize = 0;
    try testing.expectEqual(wtf8.validateCursor(invalid, &exact_cursor), wtf8.valid.validateCursor(invalid, &assume_cursor));
    try testing.expectEqual(exact_cursor, assume_cursor);
}

test "Wtf8View iterator lossy yields replacements without errors" {
    const bytes = "\xc0\xaf";
    const view = wtf8.iterator(bytes, .lossy);
    var iter = view.iterator();

    try testing.expectEqual(@as(u21, 0xfffd), iter.nextCodepoint().?);
    try testing.expectEqual(@as(u21, 0xfffd), iter.nextCodepoint().?);
    try testing.expectEqual(@as(?u21, null), iter.nextCodepoint());

    try expectWtf8LossyIteratorSlices(bytes, &.{ 1, 1 });

    iter = view.iterator();
    try testing.expectEqualStrings(prefixAfterNLossyCps(w8dfa, bytes, 2), iter.peek(2));
    try testing.expectEqual(@as(usize, 0), iter.i);
}

test "Utf8View iterator assume_valid matches exact on valid input" {
    const view = utf8.iterator(emotes, .assume_valid);
    var iter = view.iterator();
    var cursor: usize = 0;
    while (iter.nextCodepoint()) |cp| {
        const expected = try utf8.decodeCursor(emotes, &cursor);
        try testing.expectEqual(expected, cp);
    }
    try testing.expectEqual(emotes.len, cursor);

    iter = view.iterator();
    try testing.expectEqualStrings(try prefixAfterNCps(emotes, 3), iter.peek(3));
    try testing.expectEqual(@as(usize, 0), iter.i);
}

test "Utf8View iterator assume_valid nextCodepointSlice matches input slices" {
    const view = utf8.Utf8View(.assume_valid).init(emotes);
    var iter = view.iterator();
    var cursor: usize = 0;
    while (iter.nextCodepointSlice()) |cp_slice| {
        const start = cursor;
        _ = utf8.valid.decodeCursor(emotes, &cursor);
        try testing.expectEqualStrings(emotes[start..cursor], cp_slice);
    }
    try testing.expectEqual(emotes.len, cursor);
}

test "Wtf8View iterator assume_valid matches exact on valid input" {
    const view = wtf8.iterator(emotes, .assume_valid);
    var iter = view.iterator();
    var cursor: usize = 0;
    while (iter.nextCodepoint()) |cp| {
        const expected = try wtf8.decodeCursor(emotes, &cursor);
        try testing.expectEqual(expected, cp);
    }
    try testing.expectEqual(emotes.len, cursor);

    iter = view.iterator();
    try testing.expectEqualStrings(try prefixAfterNCps(emotes, 3), iter.peek(3));
    try testing.expectEqual(@as(usize, 0), iter.i);
}

test "Wtf8View iterator assume_valid nextCodepointSlice matches input slices" {
    const view = wtf8.Wtf8View(.assume_valid).init(emotes);
    var iter = view.iterator();
    var cursor: usize = 0;
    while (iter.nextCodepointSlice()) |cp_slice| {
        const start = cursor;
        _ = wtf8.valid.decodeCursor(emotes, &cursor);
        try testing.expectEqualStrings(emotes[start..cursor], cp_slice);
    }
    try testing.expectEqual(emotes.len, cursor);
}

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

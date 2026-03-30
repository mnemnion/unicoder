//! Experimental Plan 9-style UTF-8 decoder.
//!
//! This adapts the Hoehrmann byte-class/state-table decoder to the original
//! six-byte UTF-8 form. It accepts surrogate-form three-byte sequences, but it
//! still rejects all non-shortest encodings.

const Class = enum(u8) {
    ascii,
    cont_80_83,
    cont_84_87,
    cont_88_8f,
    cont_90_9f,
    cont_a0_bf,
    start_2,
    invalid,
    start_3,
    start_3_e0,
    start_4,
    start_4_f0,
    start_5,
    start_5_f8,
    start_6,
    start_6_fc,
};

const State = enum(u8) {
    accept,
    reject,
    expect_1,
    expect_2,
    expect_3,
    expect_4,
    expect_5,
    expect_2_e0,
    expect_3_f0,
    expect_4_f8,
    expect_5_fc,
};

const CLASS_COUNT = 16;
const STATE_COUNT = 11;

/// Successful codepoint parse.
pub const UTF_ACCEPT: u8 = @intFromEnum(State.accept);

/// Error state.
pub const UTF_REJECT: u8 = @intFromEnum(State.reject);

/// Error returned when the input is not well-formed Plan 9 UTF-8.
pub const DecodeError = error{InvalidUtf8};

pub const Dfa = struct {
    byte_class: [256]u8 = initByteClass(),
    class_mask: [CLASS_COUNT]u8 = .{
        0xff,
        0,
        0,
        0,
        0,
        0,
        0b0001_1111,
        0,
        0b0000_1111,
        0b0000_1111,
        0b0000_0111,
        0b0000_0111,
        0b0000_0011,
        0b0000_0011,
        0b0000_0001,
        0b0000_0001,
    },
    state_dfa: [STATE_COUNT * CLASS_COUNT]u8 = initStateDfa(),

    pub fn decode(table: Dfa, state: *u8, codepoint: *u32, byte: u8) u8 {
        const class = table.byte_class[byte];

        if (state.* == UTF_ACCEPT) {
            codepoint.* = byte & table.class_mask[class];
        } else {
            codepoint.* = (codepoint.* << 6) | (byte & 0x3f);
        }

        state.* = table.state_dfa[@as(usize, state.*) * CLASS_COUNT + class];
        return state.*;
    }

    pub fn decodeCursor(table: Dfa, bytes: []const u8, cursor: *usize) DecodeError!u32 {
        assert(cursor.* < bytes.len);

        var state: u8 = UTF_ACCEPT;
        var codepoint: u32 = 0;
        var i = cursor.*;

        while (i < bytes.len) : (i += 1) {
            switch (table.decode(&state, &codepoint, bytes[i])) {
                UTF_ACCEPT => {
                    cursor.* = i + 1;
                    return codepoint;
                },
                UTF_REJECT => {
                    cursor.* = i;
                    return error.InvalidUtf8;
                },
                else => {},
            }
        }

        cursor.* = bytes.len;
        return error.InvalidUtf8;
    }

    pub fn validate(table: Dfa, bytes: []const u8) bool {
        var state: u8 = UTF_ACCEPT;
        var codepoint: u32 = 0;

        for (bytes) |byte| {
            _ = table.decode(&state, &codepoint, byte);
            if (state == UTF_REJECT) return false;
        }

        return state == UTF_ACCEPT;
    }

    pub fn dump(table: Dfa) void {
        std.debug.print("{f}", .{table});
    }

    pub fn format(table: Dfa, writer: *std.io.Writer) std.io.Writer.Error!void {
        try writer.writeAll("// zig fmt: off\n\n");
        try writer.writeAll("const byte_class: [256]u8 = .{\n");
        try formatRows(writer, &table.byte_class, 32, 0x00);
        try writer.writeAll("};\n\n");

        try writer.writeAll("const class_mask: [16]u8 = .{\n");
        try formatPerLine(writer, &table.class_mask);
        try writer.writeAll("};\n\n");

        try writer.writeAll("const state_dfa: [176]u8 = .{\n");
        try formatRows(writer, &table.state_dfa, CLASS_COUNT, 0);
        try writer.writeAll("};\n\n");
        try writer.writeAll("// zig fmt: on\n");
    }

    fn formatRows(writer: *std.io.Writer, values: []const u8, row_len: usize, base_offset: usize) std.io.Writer.Error!void {
        var row_start: usize = 0;
        while (row_start < values.len) : (row_start += row_len) {
            try writer.writeAll("    ");

            var i = row_start;
            while (i < row_start + row_len and i < values.len) : (i += 1) {
                if (i != row_start) try writer.writeAll(",");
                try writer.print("{d}", .{values[i]});
            }

            if (row_len == 32) {
                const row_end = row_start + row_len - 1;
                try writer.print(", // {x:0>2}..{x:0>2}\n", .{
                    base_offset + row_start,
                    base_offset + row_end,
                });
            } else {
                try writer.writeAll(",\n");
            }
        }
    }

    fn formatPerLine(writer: *std.io.Writer, values: []const u8) std.io.Writer.Error!void {
        for (values) |value| {
            try writer.print("    {d},\n", .{value});
        }
    }
};

pub const dfa = Dfa{};

/// Consume one byte of Plan 9 UTF-8.
pub fn decode(state: *u8, codepoint: *u32, byte: u8) u8 {
    return dfa.decode(state, codepoint, byte);
}

/// Decode one codepoint from `bytes[cursor.*..]`, advancing `cursor` on
/// success.
pub fn decodeCursor(bytes: []const u8, cursor: *usize) DecodeError!u32 {
    return dfa.decodeCursor(bytes, cursor);
}

/// Return whether `bytes` is well-formed Plan 9 UTF-8.
pub fn validate(bytes: []const u8) bool {
    return dfa.validate(bytes);
}

fn initByteClass() [256]u8 {
    var table = [_]u8{@intFromEnum(Class.invalid)} ** 256;

    for (0x00..0x80) |byte| table[byte] = @intFromEnum(Class.ascii);
    for (0x80..0x84) |byte| table[byte] = @intFromEnum(Class.cont_80_83);
    for (0x84..0x88) |byte| table[byte] = @intFromEnum(Class.cont_84_87);
    for (0x88..0x90) |byte| table[byte] = @intFromEnum(Class.cont_88_8f);
    for (0x90..0xa0) |byte| table[byte] = @intFromEnum(Class.cont_90_9f);
    for (0xa0..0xc0) |byte| table[byte] = @intFromEnum(Class.cont_a0_bf);
    for (0xc2..0xe0) |byte| table[byte] = @intFromEnum(Class.start_2);
    for (0xe1..0xf0) |byte| table[byte] = @intFromEnum(Class.start_3);
    table[0xe0] = @intFromEnum(Class.start_3_e0);
    for (0xf1..0xf8) |byte| table[byte] = @intFromEnum(Class.start_4);
    table[0xf0] = @intFromEnum(Class.start_4_f0);
    for (0xf9..0xfc) |byte| table[byte] = @intFromEnum(Class.start_5);
    table[0xf8] = @intFromEnum(Class.start_5_f8);
    table[0xfd] = @intFromEnum(Class.start_6);
    table[0xfc] = @intFromEnum(Class.start_6_fc);

    return table;
}

fn initStateDfa() [STATE_COUNT * CLASS_COUNT]u8 {
    var table: [STATE_COUNT * CLASS_COUNT]u8 = undefined;

    for (0..STATE_COUNT) |state_i| {
        const state: State = @enumFromInt(state_i);
        for (0..CLASS_COUNT) |class_i| {
            const class: Class = @enumFromInt(class_i);
            table[state_i * CLASS_COUNT + class_i] = @intFromEnum(nextState(state, class));
        }
    }

    return table;
}

fn nextState(state: State, class: Class) State {
    return switch (state) {
        .accept => switch (class) {
            .ascii => .accept,
            .start_2 => .expect_1,
            .start_3 => .expect_2,
            .start_3_e0 => .expect_2_e0,
            .start_4 => .expect_3,
            .start_4_f0 => .expect_3_f0,
            .start_5 => .expect_4,
            .start_5_f8 => .expect_4_f8,
            .start_6 => .expect_5,
            .start_6_fc => .expect_5_fc,
            else => .reject,
        },
        .reject => .reject,
        .expect_1 => if (isContinuation(class)) .accept else .reject,
        .expect_2 => if (isContinuation(class)) .expect_1 else .reject,
        .expect_3 => if (isContinuation(class)) .expect_2 else .reject,
        .expect_4 => if (isContinuation(class)) .expect_3 else .reject,
        .expect_5 => if (isContinuation(class)) .expect_4 else .reject,
        .expect_2_e0 => switch (class) {
            .cont_a0_bf => .expect_1,
            else => .reject,
        },
        .expect_3_f0 => switch (class) {
            .cont_90_9f, .cont_a0_bf => .expect_2,
            else => .reject,
        },
        .expect_4_f8 => switch (class) {
            .cont_88_8f, .cont_90_9f, .cont_a0_bf => .expect_3,
            else => .reject,
        },
        .expect_5_fc => switch (class) {
            .cont_84_87, .cont_88_8f, .cont_90_9f, .cont_a0_bf => .expect_4,
            else => .reject,
        },
    };
}

fn isContinuation(class: Class) bool {
    return switch (class) {
        .cont_80_83,
        .cont_84_87,
        .cont_88_8f,
        .cont_90_9f,
        .cont_a0_bf,
        => true,
        else => false,
    };
}

test "decodeCursor accepts shortest forms through six bytes" {
    try expectDecode(&.{0x00}, 0x0000_0000);
    try expectDecode(&.{ 0xC2, 0x80 }, 0x0000_0080);
    try expectDecode(&.{ 0xE0, 0xA0, 0x80 }, 0x0000_0800);
    try expectDecode(&.{ 0xF0, 0x90, 0x80, 0x80 }, 0x0001_0000);
    try expectDecode(&.{ 0xF8, 0x88, 0x80, 0x80, 0x80 }, 0x0020_0000);
    try expectDecode(&.{ 0xFC, 0x84, 0x80, 0x80, 0x80, 0x80 }, 0x0400_0000);
    try expectDecode(&.{ 0xFD, 0xBF, 0xBF, 0xBF, 0xBF, 0xBF }, 0x7FFF_FFFF);
}

test "decodeCursor accepts surrogate-form sequences" {
    try expectDecode(&.{ 0xED, 0xA0, 0x80 }, 0x0000_D800);
    try expectDecode(&.{ 0xED, 0xBF, 0xBF }, 0x0000_DFFF);
}

test "decodeCursor walks mixed-width input" {
    const bytes = [_]u8{
        'A',
        0xDF,
        0xBF,
        0xED,
        0xA0,
        0x80,
        0xF0,
        0x90,
        0x80,
        0x80,
        0xF8,
        0x88,
        0x80,
        0x80,
        0x80,
        0xFC,
        0x84,
        0x80,
        0x80,
        0x80,
        0x80,
    };

    var cursor: usize = 0;
    try testing.expectEqual(@as(u32, 'A'), try decodeCursor(&bytes, &cursor));
    try testing.expectEqual(@as(u32, 0x0000_07FF), try decodeCursor(&bytes, &cursor));
    try testing.expectEqual(@as(u32, 0x0000_D800), try decodeCursor(&bytes, &cursor));
    try testing.expectEqual(@as(u32, 0x0001_0000), try decodeCursor(&bytes, &cursor));
    try testing.expectEqual(@as(u32, 0x0020_0000), try decodeCursor(&bytes, &cursor));
    try testing.expectEqual(@as(u32, 0x0400_0000), try decodeCursor(&bytes, &cursor));
    try testing.expectEqual(bytes.len, cursor);
}

test "validate rejects overlong sequences at every width" {
    try expectInvalid(&.{ 0xC0, 0x80 });
    try expectInvalid(&.{ 0xE0, 0x9F, 0xBF });
    try expectInvalid(&.{ 0xF0, 0x8F, 0xBF, 0xBF });
    try expectInvalid(&.{ 0xF8, 0x87, 0xBF, 0xBF, 0xBF });
    try expectInvalid(&.{ 0xFC, 0x83, 0xBF, 0xBF, 0xBF, 0xBF });
}

test "validate rejects truncation and impossible starters" {
    try expectInvalid(&.{ 0xE0, 0xA0 });
    try expectInvalid(&.{ 0xF8, 0x88, 0x80, 0x80 });
    try expectInvalid(&.{0x80});
    try expectInvalid(&.{ 0xC1, 0xBF });
    try expectInvalid(&.{0xFE});
    try expectInvalid(&.{0xFF});
}

test "dfa format prints the raw tables" {
    var list = try std.ArrayList(u8).initCapacity(testing.allocator, 0);
    defer list.deinit(testing.allocator);

    try std.fmt.format(list.writer(testing.allocator), "{f}", .{dfa});

    try testing.expect(std.mem.startsWith(u8, list.items, "// zig fmt: off\n\nconst byte_class"));
    try testing.expect(std.mem.indexOf(u8, list.items, "const class_mask: [16]u8 = .{") != null);
    try testing.expect(std.mem.indexOf(u8, list.items, "const state_dfa: [176]u8 = .{") != null);
    std.debug.print("{f}\n", .{dfa});
}

fn expectDecode(bytes: []const u8, want: u32) !void {
    var cursor: usize = 0;
    try testing.expect(validate(bytes));
    try testing.expectEqual(want, try decodeCursor(bytes, &cursor));
    try testing.expectEqual(bytes.len, cursor);
}

fn expectInvalid(bytes: []const u8) !void {
    var cursor: usize = 0;
    try testing.expect(!validate(bytes));
    try testing.expectError(error.InvalidUtf8, decodeCursor(bytes, &cursor));
}

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

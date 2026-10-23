const std = @import("std");

const key = @import("key.zig");
const Config = @import("Config.zig");
const tab_color = @import("tab_color.zig");
const Color = Config.Color;
const Key = key.Key;
const Value = key.Value;
const RepeatableTabColorPalette = Config.RepeatableTabColorPalette;

/// Get a value from the config by key into the given pointer. This is
/// specifically for C-compatible APIs. If you're using Zig, just access
/// the configuration directly.
///
/// The return value is false if the given key is not supported by the
/// C API yet. This is a fixable problem so if it is important to support
/// some key, please open an issue.
pub fn get(config: *const Config, k: Key, ptr_raw: *anyopaque) bool {
    @setEvalBranchQuota(10_000);
    switch (k) {
        inline else => |tag| {
            const value = fieldByKey(config, tag);
            return getValue(ptr_raw, value);
        },
    }
}

/// Get the value anytype and put it into the pointer. Returns false if
/// the type is not supported by the C API yet or the value is null.
fn getValue(ptr_raw: *anyopaque, value: anytype) bool {
    switch (@TypeOf(value)) {
        ?[:0]const u8 => {
            const ptr: *?[*:0]const u8 = @ptrCast(@alignCast(ptr_raw));
            ptr.* = if (value) |slice| @ptrCast(slice.ptr) else null;
        },

        bool => {
            const ptr: *bool = @ptrCast(@alignCast(ptr_raw));
            ptr.* = value;
        },

        u8, u32 => {
            const ptr: *c_uint = @ptrCast(@alignCast(ptr_raw));
            ptr.* = @intCast(value);
        },

        i16 => {
            const ptr: *c_short = @ptrCast(@alignCast(ptr_raw));
            ptr.* = @intCast(value);
        },

        f32, f64 => |Float| {
            const ptr: *Float = @ptrCast(@alignCast(ptr_raw));
            ptr.* = @floatCast(value);
        },

        else => |T| switch (@typeInfo(T)) {
            .optional => {
                // If an optional has no value we return false.
                const unwrapped = value orelse return false;
                return getValue(ptr_raw, unwrapped);
            },

            .@"enum" => {
                const ptr: *[*:0]const u8 = @ptrCast(@alignCast(ptr_raw));
                ptr.* = @tagName(value);
            },

            .@"struct" => |info| {
                // If the struct implements cval then we call then.
                if (@hasDecl(T, "cval")) {
                    const PtrT = @typeInfo(@TypeOf(T.cval)).@"fn".return_type.?;
                    const ptr: *PtrT = @ptrCast(@alignCast(ptr_raw));
                    ptr.* = value.cval();
                    return true;
                }

                // Packed structs that are less than or equal to the
                // size of a C int can be passed directly as their
                // bit representation.
                if (info.layout != .@"packed") return false;
                const Backing = info.backing_integer orelse return false;
                if (@bitSizeOf(Backing) > @bitSizeOf(c_uint)) return false;

                const ptr: *c_uint = @ptrCast(@alignCast(ptr_raw));
                ptr.* = @intCast(@as(Backing, @bitCast(value)));
            },

            .@"union" => {
                if (@hasDecl(T, "cval")) {
                    const PtrT = @typeInfo(@TypeOf(T.cval)).@"fn".return_type.?;
                    const ptr: *PtrT = @ptrCast(@alignCast(ptr_raw));
                    ptr.* = value.cval();
                    return true;
                }

                return false;
            },

            else => return false,
        },
    }

    return true;
}

/// Get a value from the config by key.
fn fieldByKey(self: *const Config, comptime k: Key) Value(k) {
    const field = comptime field: {
        const fields = std.meta.fields(Config);
        for (fields) |field| {
            if (@field(Key, field.name) == k) {
                break :field field;
            }
        }

        unreachable;
    };

    return @field(self, field.name);
}

test "c_get: u8" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();
    c.@"font-size" = 24;

    var cval: f32 = undefined;
    try testing.expect(get(&c, .@"font-size", &cval));
    try testing.expectEqual(@as(f32, 24), cval);
}

test "c_get: enum" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();
    c.@"window-theme" = .dark;

    var cval: [*:0]u8 = undefined;
    try testing.expect(get(&c, .@"window-theme", @ptrCast(&cval)));

    const str = std.mem.sliceTo(cval, 0);
    try testing.expectEqualStrings("dark", str);
}

test "c_get: color" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();
    c.background = .{ .r = 255, .g = 0, .b = 0 };

    var cval: Color.C = undefined;
    try testing.expect(get(&c, .background, @ptrCast(&cval)));
    try testing.expectEqual(255, cval.r);
    try testing.expectEqual(0, cval.g);
    try testing.expectEqual(0, cval.b);
}

test "c_get: optional" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();

    {
        c.@"unfocused-split-fill" = null;
        var cval: Color.C = undefined;
        try testing.expect(!get(&c, .@"unfocused-split-fill", @ptrCast(&cval)));
    }

    {
        c.@"unfocused-split-fill" = .{ .r = 255, .g = 0, .b = 0 };
        var cval: Color.C = undefined;
        try testing.expect(get(&c, .@"unfocused-split-fill", @ptrCast(&cval)));
        try testing.expectEqual(255, cval.r);
        try testing.expectEqual(0, cval.g);
        try testing.expectEqual(0, cval.b);
    }
}

test "c_get: background-blur" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();

    {
        c.@"background-blur" = .false;
        var cval: i16 = undefined;
        try testing.expect(get(&c, .@"background-blur", @ptrCast(&cval)));
        try testing.expectEqual(0, cval);
    }
    {
        c.@"background-blur" = .true;
        var cval: i16 = undefined;
        try testing.expect(get(&c, .@"background-blur", @ptrCast(&cval)));
        try testing.expectEqual(20, cval);
    }
    {
        c.@"background-blur" = .{ .radius = 42 };
        var cval: i16 = undefined;
        try testing.expect(get(&c, .@"background-blur", @ptrCast(&cval)));
        try testing.expectEqual(42, cval);
    }
    {
        c.@"background-blur" = .@"macos-glass-regular";
        var cval: i16 = undefined;
        try testing.expect(get(&c, .@"background-blur", @ptrCast(&cval)));
        try testing.expectEqual(-1, cval);
    }
    {
        c.@"background-blur" = .@"macos-glass-clear";
        var cval: i16 = undefined;
        try testing.expect(get(&c, .@"background-blur", @ptrCast(&cval)));
        try testing.expectEqual(-2, cval);
    }
}

test "c_get: split-preserve-zoom" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();

    var bits: c_uint = undefined;
    try testing.expect(get(&c, .@"split-preserve-zoom", @ptrCast(&bits)));
    try testing.expectEqual(@as(c_uint, 0), bits);

    c.@"split-preserve-zoom".navigation = true;
    try testing.expect(get(&c, .@"split-preserve-zoom", @ptrCast(&bits)));
    try testing.expectEqual(@as(c_uint, 1), bits);
}

test "c_get: tab_color_palette" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();

    // Empty palette should return empty list
    const empty_ptr: *const tab_color.TabColorPaletteListC = @ptrCast(&c.@"tab-color-palette");
    try testing.expectEqual(@as(usize, 0), empty_ptr.len);

    // Parse a palette entry. Config values are owned by the config's arena.
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    try c.@"tab-color-palette".parseCLI(arena.allocator(), "nord:bg=#2e3440,fg=#d8dee9");

    const ptr: *const tab_color.TabColorPaletteListC = @ptrCast(&c.@"tab-color-palette");
    try testing.expectEqual(@as(usize, 1), ptr.len);
}

test "c_get: tab colors" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();

    // Unset tab colors report no value.
    var color: Config.Color.C = undefined;
    try testing.expect(!get(&c, .@"tab-background-active", @ptrCast(&color)));
    try testing.expect(!get(&c, .@"tab-foreground-inactive", @ptrCast(&color)));

    var opacity: f64 = 0;
    try testing.expect(get(&c, .@"tab-background-opacity", @ptrCast(&opacity)));
    try testing.expectEqual(@as(f64, 1.0), opacity);

    c.@"tab-background-active" = .{ .r = 1, .g = 2, .b = 3 };
    try testing.expect(get(&c, .@"tab-background-active", @ptrCast(&color)));
    try testing.expectEqual(@as(u8, 1), color.r);
    try testing.expectEqual(@as(u8, 2), color.g);
    try testing.expectEqual(@as(u8, 3), color.b);
}

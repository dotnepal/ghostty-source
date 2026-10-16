const std = @import("std");
const AllocatorError = std.mem.Allocator.Error;
const formatterpkg = @import("formatter.zig");
pub const ParseError = AllocatorError || error{
    InvalidFormat,
    InvalidColor,
};

/// TabColorPalette represents a single named color palette entry for
/// the right-click tab color picker.
///
/// Each entry has a name, an active bg/fg, and optional inactive bg/fg.
/// When inactive colors are not set they default to a dimmed version
/// of the active colors.
pub const TabColorPalette = struct {
    /// The palette name. Must be unique across all entries.
    name: []const u8,

    /// Active tab background color (RGB).
    bg: ?[3]u8,

    /// Active tab foreground color (RGB).
    fg: ?[3]u8,

    /// Inactive tab background color (RGB). Optional; defaults to dimmed bg.
    inactive_bg: ?[3]u8,

    /// Inactive tab foreground color (RGB). Optional; defaults to dimmed fg.
    inactive_fg: ?[3]u8,

    pub fn init(alloc: std.mem.Allocator, name: []const u8) AllocatorError!TabColorPalette {
        return .{
            .name = try alloc.dupe(u8, name),
            .bg = null,
            .fg = null,
            .inactive_bg = null,
            .inactive_fg = null,
        };
    }

    pub fn deinit(self: *TabColorPalette, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        self.name = undefined;
    }

    /// Parse a single palette entry from a config line:
    /// `name:bg=#RRGGBB,fg=#RRGGBB,inactive-bg=#RRGGBB,inactive-fg=#RRGGBB`
    pub fn parse(alloc: std.mem.Allocator, input: []const u8) ParseError!TabColorPalette {
        var palette = try TabColorPalette.init(alloc, "");
        errdefer palette.deinit(alloc);

        const colon_idx = std.mem.indexOfScalar(u8, input, ':') orelse {
            return error.InvalidFormat;
        };
        const name = input[0..colon_idx];
        if (name.len == 0) return error.InvalidFormat;

        // Allocate the name
        palette.name = try alloc.dupe(u8, name);
        palette.bg = null;
        palette.fg = null;
        palette.inactive_bg = null;
        palette.inactive_fg = null;

        const kv_string = input[colon_idx + 1 ..];
        try parseKeyValuePairs(&palette, kv_string);

        return palette;
    }

    fn parseKeyValuePairs(palette: *TabColorPalette, kv_string: []const u8) ParseError!void {
        var it = std.mem.splitScalar(u8, kv_string, ',');
        while (it.next()) |pair| {
            const eq_idx = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
            const key = pair[0..eq_idx];
            const value = pair[eq_idx + 1 ..];

            if (std.mem.eql(u8, key, "bg")) {
                palette.bg = try parseColor(value);
            } else if (std.mem.eql(u8, key, "fg")) {
                palette.fg = try parseColor(value);
            } else if (std.mem.eql(u8, key, "inactive-bg")) {
                palette.inactive_bg = try parseColor(value);
            } else if (std.mem.eql(u8, key, "inactive-fg")) {
                palette.inactive_fg = try parseColor(value);
            }
            // Unknown keys are silently ignored
        }
    }

    fn parseColor(value: []const u8) ParseError!(?[3]u8) {
        // Skip leading '#' if present
        const hex = if (value.len > 0 and value[0] == '#') value[1..] else value;

        // Validate hex string: must be exactly 6 characters
        if (hex.len != 6) return error.InvalidColor;

        var rgb: [3]u8 = undefined;
        for (0..3) |i| {
            const hi = hex[i * 2];
            const lo = hex[i * 2 + 1];
            const hi_val = hexToNibble(hi) orelse return error.InvalidColor;
            const lo_val = hexToNibble(lo) orelse return error.InvalidColor;
            rgb[i] = @as(u8, hi_val) << 4 | @as(u8, lo_val);
        }
        return rgb;
    }

    fn hexToNibble(c: u8) ?u4 {
        return switch (c) {
            '0' => @intCast(c - '0'),
            '1' => @intCast(c - '0'),
            '2' => @intCast(c - '0'),
            '3' => @intCast(c - '0'),
            '4' => @intCast(c - '0'),
            '5' => @intCast(c - '0'),
            '6' => @intCast(c - '0'),
            '7' => @intCast(c - '0'),
            '8' => @intCast(c - '0'),
            '9' => @intCast(c - '0'),
            'a', 'A' => 10,
            'b', 'B' => 11,
            'c', 'C' => 12,
            'd', 'D' => 13,
            'e', 'E' => 14,
            'f', 'F' => 15,
            else => null,
        };
    }
};

// C-compatible representation for the FFI layer.
// Matches ghostty_config_tab_color_palette_s in ghostty.h.
pub const TabColorPaletteC = extern struct {
    name: [*c]const u8,
    name_len: u32,
    bg: [3]u8,
    fg: [3]u8,
    inactive_bg: [3]u8,
    inactive_fg: [3]u8,
    has_inactive_bg: u8,
    has_inactive_fg: u8,
};

// C-compatible list representation for the FFI layer.
// Matches ghostty_config_tab_color_palette_list_s in ghostty.h.
pub const TabColorPaletteListC = extern struct {
    palettes: [*]const TabColorPaletteC,
    len: usize,
};

// Internal buffer type for syncing Zig data to C representation.
const PaletteCBuffer = struct {
    palettes: [*c]TabColorPaletteC,
    count: usize,
    capacity: usize,
};

/// RepeatableTabColorPalette holds a list of named tab color palettes.
/// Each entry is a unique palette for the right-click tab color picker.
pub const RepeatableTabColorPalette = struct {
    value: std.ArrayList(TabColorPalette) = .empty,
    value_c: PaletteCBuffer = .{
        .palettes = @ptrFromInt(0),
        .count = 0,
        .capacity = 0,
    },

    /// Parse a single CLI value and append to the list.
    /// Duplicate names overwrite earlier entries with the same name.
    pub fn parseCLI(self: *RepeatableTabColorPalette, alloc: std.mem.Allocator, input: ?[]const u8) ParseError!void {
        if (input == null or input.?.len == 0) {
            self.value.clearRetainingCapacity();
            self.value_c.count = 0;
            return;
        }

        const item = try TabColorPalette.parse(alloc, input.?);

        // Check for duplicate name; if found, remove the old entry
        for (self.value.items, 0..) |*existing, i| {
            if (std.mem.eql(u8, existing.name, item.name)) {
                existing.deinit(alloc);
                _ = self.value.swapRemove(i);
                break;
            }
        }

        try self.value.append(alloc, item);
        self.syncValueC(alloc) catch {};
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: *const RepeatableTabColorPalette, alloc: std.mem.Allocator) AllocatorError!RepeatableTabColorPalette {
        var value = try std.ArrayListUnmanaged(TabColorPalette).initCapacity(
            alloc,
            self.value.items.len,
        );
        errdefer {
            for (value.items) |*item| item.deinit(alloc);
            value.deinit(alloc);
        }

        for (self.value.items) |*item| {
            const name = try alloc.dupe(u8, item.name);
            value.appendAssumeCapacity(.{
                .name = name,
                .bg = item.bg,
                .fg = item.fg,
                .inactive_bg = item.inactive_bg,
                .inactive_fg = item.inactive_fg,
            });
        }

        var result: RepeatableTabColorPalette = .{
            .value = value,
        };
        result.syncValueC(alloc) catch {};
        return result;
    }

    /// Compare if two values are equal. Required by Config.
    pub fn equal(self: RepeatableTabColorPalette, other: RepeatableTabColorPalette) bool {
        if (self.value.items.len != other.value.items.len) return false;
        for (self.value.items, other.value.items) |a, b| {
            if (!std.mem.eql(u8, a.name, b.name)) return false;
            if (!colorsEqual(a.bg, b.bg)) return false;
            if (!colorsEqual(a.fg, b.fg)) return false;
            if (!colorsEqual(a.inactive_bg, b.inactive_bg)) return false;
            if (!colorsEqual(a.inactive_fg, b.inactive_fg)) return false;
        }
        return true;
    }

    fn colorsEqual(a: ?[3]u8, b: ?[3]u8) bool {
        if (a == null and b == null) return true;
        if (a == null or b == null) return false;
        return std.mem.eql(u8, &a.?, &b.?);
    }

    /// Sync value_c from value for C API access.
    /// Call this before cval() to ensure the C pointer is up-to-date.
    fn syncValueC(self: *RepeatableTabColorPalette, alloc: std.mem.Allocator) AllocatorError!void {
        const len = self.value.items.len;
        if (self.value_c.count == len) {
            // Same size, just update the data in-place
            var i: usize = 0;
            while (i < len) : (i += 1) {
                const c = &self.value_c.palettes[i];
                const zig = self.value.items[i];
                c.name = zig.name.ptr;
                c.name_len = @intCast(zig.name.len);
                c.bg = zig.bg orelse [3]u8{ 0, 0, 0 };
                c.fg = zig.fg orelse [3]u8{ 0, 0, 0 };
                c.inactive_bg = zig.inactive_bg orelse [3]u8{ 0, 0, 0 };
                c.inactive_fg = zig.inactive_fg orelse [3]u8{ 0, 0, 0 };
                c.has_inactive_bg = if (zig.inactive_bg != null) 1 else 0;
                c.has_inactive_fg = if (zig.inactive_fg != null) 1 else 0;
            }
        } else {
            // Size changed — recreate value_c
            if (self.value_c.capacity > 0) {
                alloc.free(self.value_c.palettes[0..self.value_c.capacity]);
            }
            self.value_c.palettes = @ptrCast((try alloc.alloc(TabColorPaletteC, len)).ptr);
            self.value_c.count = len;
            self.value_c.capacity = len;
            for (self.value.items) |zig| {
                self.value_c.palettes[self.value_c.count] = .{
                    .name = zig.name.ptr,
                    .name_len = @intCast(zig.name.len),
                    .bg = zig.bg orelse [3]u8{ 0, 0, 0 },
                    .fg = zig.fg orelse [3]u8{ 0, 0, 0 },
                    .inactive_bg = zig.inactive_bg orelse [3]u8{ 0, 0, 0 },
                    .inactive_fg = zig.inactive_fg orelse [3]u8{ 0, 0, 0 },
                    .has_inactive_bg = if (zig.inactive_bg != null) 1 else 0,
                    .has_inactive_fg = if (zig.inactive_fg != null) 1 else 0,
                };
                self.value_c.count += 1;
            }
        }
    }

    /// Used by FileFormatter
    pub fn formatEntry(self: RepeatableTabColorPalette, formatter: formatterpkg.EntryFormatter) !void {
        if (self.value.items.len == 0) {
            try formatter.formatEntry(void, {});
            return;
        }

        for (self.value.items) |item| {
            var hex_buf: [7]u8 = undefined;
            var kv_buf: [256]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&kv_buf);

            writer.writeAll(item.name) catch return error.OutOfMemory;
            writer.writeByte(':') catch return error.OutOfMemory;

            if (item.bg) |bg| {
                writer.writeAll("bg=") catch return error.OutOfMemory;
                const hex = toHex(bg, &hex_buf) orelse return error.OutOfMemory;
                writer.writeAll(hex) catch return error.OutOfMemory;
            }

            if (item.fg) |fg| {
                writer.writeAll(",fg=") catch return error.OutOfMemory;
                const hex = toHex(fg, &hex_buf) orelse return error.OutOfMemory;
                writer.writeAll(hex) catch return error.OutOfMemory;
            }

            if (item.inactive_bg) |bg| {
                writer.writeAll(",inactive-bg=") catch return error.OutOfMemory;
                const hex = toHex(bg, &hex_buf) orelse return error.OutOfMemory;
                writer.writeAll(hex) catch return error.OutOfMemory;
            }

            if (item.inactive_fg) |fg| {
                writer.writeAll(",inactive-fg=") catch return error.OutOfMemory;
                const hex = toHex(fg, &hex_buf) orelse return error.OutOfMemory;
                writer.writeAll(hex) catch return error.OutOfMemory;
            }

            try formatter.formatEntry([]const u8, writer.buffered());
        }
    }

    fn toHex(color: ?[3]u8, buf: []u8) ?[]const u8 {
        if (color == null) return null;
        const rgb = color.?;
        // Format as #RRGGBB
        buf[0] = '#';
        for (0..3) |i| {
            const hex_chars = "0123456789abcdef";
            buf[1 + i * 2] = hex_chars[@divTrunc(rgb[i], 16)];
            buf[2 + i * 2] = hex_chars[rgb[i] % 16];
        }
        return buf[0..7];
    }

    /// Return the C-compatible representation of this palette list.
    pub fn cval(self: *const RepeatableTabColorPalette) TabColorPaletteListC {
        return .{
            .palettes = self.value_c.palettes,
            .len = self.value_c.count,
        };
    }

    test "RepeatableTabColorPalette parseCLI" {
        const testing = std.testing;
        const alloc = testing.allocator;

        var list: RepeatableTabColorPalette = .{};

        // Parse a basic palette entry
        try list.parseCLI(alloc, "nord:bg=#2e3440,fg=#d8dee9");
        try testing.expectEqual(@as(usize, 1), list.value.items.len);
        try testing.expectEqualStrings("nord", list.value.items[0].name);
        try testing.expect(list.value.items[0].bg != null);
        try testing.expect(list.value.items[0].fg != null);
        try testing.expect(list.value.items[0].inactive_bg == null);
        try testing.expect(list.value.items[0].inactive_fg == null);

        // Parse with all fields
        try list.parseCLI(alloc, "dracula:bg=#282a36,fg=#f8f8f2,inactive-bg=#1e1f29,inactive-fg=#6272a4");
        try testing.expectEqual(@as(usize, 2), list.value.items.len);
        try testing.expect(list.value.items[1].inactive_bg != null);
        try testing.expect(list.value.items[1].inactive_fg != null);

        // Duplicate name overwrites
        try list.parseCLI(alloc, "nord:bg=#1a1b26,fg=#a9b1d6");
        try testing.expectEqual(@as(usize, 2), list.value.items.len);
        try testing.expectEqualStrings("nord", list.value.items[1].name);

        // Empty clears
        try list.parseCLI(alloc, "");
        try testing.expectEqual(@as(usize, 0), list.value.items.len);
    }

    test "RepeatableTabColorPalette clone" {
        const testing = std.testing;
        const alloc = testing.allocator;

        var list: RepeatableTabColorPalette = .{};
        try list.parseCLI(alloc, "test:bg=#aabbcc,fg=#ddeeff");
        try list.parseCLI(alloc, "test2:bg=#112233");

        const cloned = try list.clone(alloc);
        try testing.expectEqual(list.value.items.len, cloned.value.items.len);
        try testing.expect(std.mem.eql(u8, list.value.items[0].name, cloned.value.items[0].name));
        try testing.expect(list.value.items[0].bg.? != cloned.value.items[0].bg.?);
        try testing.expect(std.mem.eql(u8, &list.value.items[0].bg.?, &cloned.value.items[0].bg.?));
    }

    test "RepeatableTabColorPalette equal" {
        const testing = std.testing;
        const alloc = testing.allocator;

        var a: RepeatableTabColorPalette = .{};
        var b: RepeatableTabColorPalette = .{};
        try a.parseCLI(alloc, "test:bg=#aabbcc");
        try b.parseCLI(alloc, "test:bg=#aabbcc");
        try testing.expect(a.equal(b));

        try b.parseCLI(alloc, "test2:bg=#ddeeff");
        try testing.expect(!a.equal(b));
    }
};

test {
    _ = RepeatableTabColorPalette;
}

# Colorful Tabs — Contract

> Freeze date: 2026-10-16
> Branch: `colorful-tabs` on `dotnepal/ghostty-source`

## 1. Config keys

All keys are optional. If **none** are set, tabs behave exactly as they do today.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `tab-background-active` | `?Color` | — | Tab background for the focused/active tab. Hex or named X11 color. |
| `tab-foreground-active` | `?Color` | — | Tab foreground (text) for the active tab. |
| `tab-background-inactive` | `?Color` | Dimmed `tab-background-active` | Tab background for inactive tabs. |
| `tab-foreground-inactive` | `?Color` | Dimmed `tab-foreground-active` | Tab foreground for inactive tabs. |
| `tab-background-opacity` | `f64` | `1.0` | Shared by active and inactive. Clamped to [0.01, 1.0]. |
| `tab-color-palette` | `RepeatableTabColorPalette` | — | Named palette for the right-click tab color picker. Repeatable. |

## 2. `tab-color-palette` syntax

```
tab-color-palette = name:bg=#RRGGBB,fg=#RRGGBB,inactive-bg=#RRGGBB,inactive-fg=#RRGGBB
```

- **`name`** — alphanumeric, no spaces. Must be unique across all entries.
- **`bg`** — required. Hex `#RRGGBB` or `RRGGBB`.
- **`fg`** — required. Same format.
- **`inactive-bg`** — optional. Defaults to a dimmed version of `bg`.
- **`inactive-fg`** — optional. Defaults to a dimmed version of `fg`.

Unknown keys are silently ignored. Duplicate names: later entry overwrites earlier.

## 3. Color resolution order

Highest priority first:

1. **Per-tab color** (picked via right-click palette), resolved through the named `tab-color-palette` entry.
2. **Config keys** `tab-*-active` / `tab-*-inactive`.
3. **Default**: Ghostty's existing tab behavior (no change).

Then macOS accessibility preferences are applied:
- **Reduce Transparency**: forces `tab-background-opacity` to `1.0`.
- **Increase Contrast**: forces foreground to meet 4.5:1 contrast ratio against background.
- **Light / dark appearance**: the built-in palette has light/dark variants.

## 4. C struct layout (for `c_get.zig`)

```zig
pub const TabColorPalette = extern struct {
    name: []const u8,
    bg: ?[3]u8,       // RGB, null means "use default"
    fg: ?[3]u8,
    inactive_bg: ?[3]u8,
    inactive_fg: ?[3]u8,
};

pub const TabColorConfig = extern struct {
    background_active: ?[3]u8,
    foreground_active: ?[3]u8,
    background_inactive: ?[3]u8,
    foreground_inactive: ?[3]u8,
    opacity: f64,
    palettes: []const TabColorPalette,
};
```

## 5. Inactive dimming formula

When `tab-*-inactive` is not configured and the active equivalent is:

- `inactive-bg` = `active-bg * 0.65` (65% luminance)
- `inactive-fg` = `active-fg * 0.65` (65% luminance)

The factor 0.65 matches macOS tab dimming behavior.

## 6. File locations

| Concern | File |
|---------|------|
| Config struct + keys + doc comments | `src/config/Config.zig` |
| Config parser (repeatable type) | `src/config/Config.zig` (follow `RepeatablePath` pattern) |
| Config round-trip + parse tests | `src/config/Config.zig` (`test` blocks) |
| C bridge | `src/config/c_get.zig` + `include/ghostty.h` |
| Swift accessors | `macos/Sources/Ghostty/Ghostty.Config.swift` |
| DerivedConfig carrier | `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` |
| Color resolver (`TabColorStyle`) | `macos/Sources/Features/Terminal/TerminalTabColor.swift` |
| Color resolver tests | `macos/Tests/Terminal/` |
| Tab painting | `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` |
| Titlebar tabs (Sequoia+) | `macos/Sources/Features/Terminal/Window Styles/TitlebarTabsSequoiaTerminalWindow.swift` |
| Right-click palette UI | `macos/Sources/Features/Terminal/TerminalTabColor.swift` |

## 7. Doc comment convention

For `+show-config --docs` and `+edit-config` integration, follow existing patterns in `Config.zig`:

```zig
/// Short description of what the config key does.
///
/// More details in paragraphs.
///
/// Example: `key = value`
///
/// Available since: X.X.X
@"config-key-name": FieldType = defaultValue,
```

Doc comments are scanned by `helpgen.zig` at build time — no separate doc file needed.

## 8. Opacity clamping

`tab-background-opacity` is clamped to `[0.01, 1.0]`:
- Values < 0.01 become 0.01 (near-transparent but not fully invisible).
- Values > 1.0 become 1.0 (solid).

## 9. Fallback

When a tab can't be painted (hidden titlebar, missing private views on a future macOS), fall back to the existing colored dot indicator using the palette's `bg` color.

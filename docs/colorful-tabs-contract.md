# Colorful Tabs — Contract

> Frozen: 2026-10-16. Synced with the implementation: 2026-10-23.
> Branch: `colorful-tabs` on `dotnepal/ghostty-source`
> Platform: macOS only. The keys have no effect on Linux (GTK).

Changes since the freeze are marked **(synced)**.

## 1. Config keys

All keys are optional. If **none** are set, tabs behave exactly as they do today.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `tab-background-active` | `?Color` | — | Tab background for the selected tab. Hex or named X11 color. |
| `tab-foreground-active` | `?Color` | — | Tab foreground (text) for the selected tab. |
| `tab-background-inactive` | `?Color` | `tab-background-active` dimmed to 65% | Tab background for the other tabs. |
| `tab-foreground-inactive` | `?Color` | `tab-foreground-active` dimmed to 65% | Tab foreground for the other tabs. |
| `tab-background-opacity` | `f64` | `1.0` | Shared by active and inactive tabs. Clamped to [0.01, 1.0]. |
| `tab-color-palette` | `RepeatableTabColorPalette` | — | Named palette for the right-click tab color picker. Repeatable. |

**(synced)** Config keys are declared in kebab-case in `Config.zig`
(`@"tab-background-active"`), like every other key; the parser matches names
literally. `cell-background` and `cell-foreground` are **not** supported values.

## 2. `tab-color-palette` syntax

```
tab-color-palette = name:bg=#RRGGBB,fg=#RRGGBB,inactive-bg=#RRGGBB,inactive-fg=#RRGGBB
```

- **`name`** — letters and digits only, no spaces. **(synced)** Matched to the
  picker swatches, see below.
- **`bg`** — required. Hex `#RRGGBB` or `RRGGBB`.
- **`fg`** — required. Same format.
- **`inactive-bg`** — optional. Defaults to `bg` dimmed to 65%.
- **`inactive-fg`** — optional. Defaults to `fg` dimmed to 65%.

An entry missing `bg` or `fg`, with a bad color, or with a name that is empty or
not alphanumeric is a config error. Unknown keys are silently ignored. A
duplicate name replaces the earlier entry in place (it keeps its position).
An empty value clears the list.

### Picker swatches **(synced)**

The right-click picker has nine swatches: `blue`, `purple`, `pink`, `red`,
`orange`, `yellow`, `green`, `teal`, `graphite` (plus "None"). An entry changes
the swatch with the same name, ignoring case; a later entry wins. A swatch with
no entry keeps its system color. An entry with any other name has no swatch.
The picked color is still stored as the built-in enum (`TerminalTabColor`), so
saved/restored and undone tab colors are unchanged.

## 3. Color resolution order

Per tab, highest priority first:

1. **A picked color** (right-click menu).
   - With a palette entry of the same name: the entry's `bg`, `fg`,
     `inactive-bg`, `inactive-fg` (missing inactive values are dimmed from the
     active ones). The `tab-*` keys are **not** consulted, so the entry's `fg`
     wins over `tab-foreground-active`.
   - With no such entry: the system color is the background, the text color is
     `tab-foreground-active` / `tab-foreground-inactive`, and the inactive
     background is the system color dimmed to 65%.
2. **Config keys** `tab-*-active` / `tab-*-inactive`, for tabs with no picked
   color. A palette alone never colors tabs without a picked color.
3. **Default**: Ghostty's existing tab look. Nothing is painted, and anything
   painted earlier is removed.

Unset inactive colors are the active colors with their RGB components scaled by
0.65 (alpha is kept).

Then macOS accessibility and appearance settings are applied **(synced)**:
- **Reduce Transparency**: forces the opacity to `1.0`.
- **Increase Contrast**: a foreground with less than 4.5:1 contrast against its
  background becomes black or white, whichever contrasts more.
- **Light / dark appearance**: system colors are resolved against the window's
  appearance. There is no separate built-in light/dark palette (decision 1: no
  built-in preset).

## 4. C bridge **(synced)**

Only the palette needs a struct (`include/ghostty.h`, `src/config/tab_color.zig`).
The other keys use the existing `?Color` (`ghostty_config_color_s`) and `f64`
getters; there is no combined config struct.

```c
typedef struct {
  const char* name;
  uint32_t name_len;
  uint8_t bg[3];
  uint8_t fg[3];
  uint8_t inactive_bg[3];
  uint8_t inactive_fg[3];
  uint8_t has_inactive_bg;   // 0 = unset, the zeroed inactive_bg is not a color
  uint8_t has_inactive_fg;
} ghostty_config_tab_color_palette_s;

typedef struct {
  const ghostty_config_tab_color_palette_s* palettes;  // NULL when empty
  size_t len;
} ghostty_config_tab_color_palette_list_s;
```

`palettes` is NULL for an empty list; callers must check `len` first.
`bg` and `fg` are always set.

## 5. Inactive dimming

When an inactive color is not configured: `inactive = active * 0.65`, applied to
each RGB component. The factor is `TabColorStyle.inactiveDimFactor`. **(synced)**
It is not a luminance calculation.

## 6. Painting **(synced)**

- Only visible tab bars are painted. macOS hides the bar when a window has a
  single tab, so nothing is colored then.
- Each tab is painted from its own style, on an overlay view
  (`TabColorOverlayView`, identifier `com.mitchellh.ghostty.tabColorOverlay`)
  inside that tab's `_backgroundView`. AppKit resets the layer color of its own
  views whenever it redraws a tab, so the overlay is used instead. It ignores
  mouse events. The tab's button is found by walking up from the tab's
  accessory view to its `NSTabButton`.
- Backgrounds use `tab-background-opacity` as alpha.
- Titles are colored through `tab.attributedTitle` (public API).
- Tabs repaint on becoming main or losing key, when the tab bar appears,
  on config sync, when a tab color changes, on `effectiveAppearance` changes
  and on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
- With no tab colors configured, AppKit's own painting is left alone. If a
  style that was painted goes back to the default, the overlay is removed.
- On Sequoia titlebar tabs (`TitlebarTabsVenturaTerminalWindow`), the
  very-dark-background treatment does not overwrite a configured tab color.

## 7. Opacity clamping

`tab-background-opacity` is clamped to `[0.01, 1.0]`:
- Values < 0.01 become 0.01 (near-transparent but not fully invisible).
- Values > 1.0 become 1.0 (solid).

**(synced)** The Zig config stores the raw value. The clamp is applied in
`TabColorStyle.resolve`.

## 8. Fallback

When a tab can't be painted (hidden titlebar, missing private views on a future
macOS), the tab shows the existing colored dot instead, in the tab's resolved
active background color. **(synced)** The dot is also shown whenever a color is
picked, as it was before this feature; with only config keys it appears only
when painting fails.

## 9. File locations **(synced)**

| Concern | File |
|---------|------|
| Config keys and doc comments | `src/config/Config.zig` |
| Palette type, parser, C view, Zig tests | `src/config/tab_color.zig` |
| Config load test, `c_get` tests | `src/config/Config.zig`, `src/config/c_get.zig` |
| C bridge | `src/config/c_get.zig` + `include/ghostty.h` |
| Swift accessors | `macos/Sources/Ghostty/Ghostty.Config.swift` |
| DerivedConfig carrier, tab painting, dot, picker menu hookup | `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` |
| Color resolver (`TabColorStyle`), palette lookup, picker view | `macos/Sources/Features/Terminal/TerminalTabColor.swift` |
| Config push before repaint | `macos/Sources/Features/Terminal/TerminalController.swift` |
| Titlebar tabs on macOS 15 and older | `macos/Sources/Features/Terminal/Window Styles/TitlebarTabsVenturaTerminalWindow.swift` |
| Titlebar tabs on macOS 26+ | `macos/Sources/Features/Terminal/Window Styles/TitlebarTabsTahoeTerminalWindow.swift` (untested, falls back to the dot) |
| Color resolver tests | `macos/Tests/Terminal/` (not written yet) |

## 10. Doc comment convention

For `+show-config --docs` and `+edit-config` integration, follow existing
patterns in `Config.zig`:

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

Doc comments are scanned by `helpgen.zig` at build time — no separate doc file
needed. The palette key's doc comment carries the walkthrough (swatch names,
resolution order, accessibility).

## 11. Known gaps **(synced)**

- The keys are marked `Available since: 1.4.0`, the label upstream uses for
  unreleased features (the latest release is 1.3.1, `main` is 1.3.2-dev). The
  maintainers may want a different version at merge time.
- Palette entries whose names don't match a swatch are unreachable from the
  picker.
- No Swift unit tests for the resolver. Not tested on macOS 26.

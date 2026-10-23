# Ghostty colorful tabs: plan and status

Single source of truth for this feature. Replaces `colorful-tabs-plan.md`,
`colorful-tabs-plan-claude.md` and `HANDOFF.md`.
The frozen spec (key names, types, C struct layout) stays in `docs/colorful-tabs-contract.md`.

Status: Wave 0 done, Wave 1 done (except push), Wave 2 Task 1 partly done. Nothing pushed yet.
Last synced against branch `colorful-tabs` at `7bd0efd` (2026-10-23).
Source analysed: `ghostty-org/ghostty` at `b3dc3d7` (2026-10-15).
Repo: `dotnepal/ghostty-source` (a clone of ghostty-org/ghostty, not a GitHub fork yet).

## Goal

iTerm-style colored tabs on macOS, driven by the Ghostty config:

- Configurable from `ghostty +edit-config`, reloads live.
- Solid or transparent background via a single `tab-background-opacity`.
- Background and foreground configurable separately, for the active and inactive tab.
- When no tab-color config is set, tabs behave exactly as they do today (no change).
- Respects user preference: a color picked on a tab overrides config, and macOS
  Reduce Transparency, Increase Contrast and light/dark mode are honoured.
- Falls back gracefully to the existing colored dot where the system can't paint the tab.

## Config surface

```ini
tab-background-active   = #1e66f5
tab-foreground-active   = #ffffff
tab-background-inactive = #16408f   # unset: dimmed active bg
tab-foreground-inactive = #c8c8c8   # unset: dimmed active fg
tab-background-opacity  = 1.0       # 1.0 solid, <1.0 transparent; shared by active and inactive

# Repeatable. Defines a named palette for the right-click tab color picker.
# Each entry uses comma-separated key=value pairs.
tab-color-palette = red:bg=#e64553,fg=#ffffff,inactive-bg=#7a2a33,inactive-fg=#d0d0d0
```

Resolution order for a tab's colors, highest first:
1. Per-tab color (right-click picker), resolved through `tab-color-palette`.
2. `tab-*-active` / `tab-*-inactive` keys.
3. If no tab color config exists at all, Ghostty's default tab behavior is used unchanged.

Then macOS preferences adjust the result: Reduce Transparency forces opacity 1.0,
Increase Contrast forces a foreground that meets 4.5:1 against the background, and
light/dark appearance is honoured.

## Decisions

1. **No built-in preset fallback.** With no tab-color config, tabs look exactly as today.
2. **Key renamed** from `tab-color-preset` to `tab-color-palette` (repeatable).
3. **Palette syntax:** `name:bg=#RRGGBB,fg=#RRGGBB,inactive-bg=#RRGGBB,inactive-fg=#RRGGBB`; unknown keys are ignored, duplicate names overwrite.
4. **Inactive dimming factor:** 0.65 (65% luminance) for bg and fg when not configured.
5. **Opacity clamping:** [0.01, 1.0].
6. **Fallback:** colored dot in the palette's bg color when tab painting fails.
7. **Docs via doc comments** in `Config.zig`; `helpgen.zig` picks them up for `+show-config --docs` and `+edit-config`. No separate doc file.
8. **Testing deferred.** Sam tests manually first; automated tests come later.
9. **Sequential waves.** Zig config before Swift bridge before resolver; painting before palettes/fallback.
10. **Single build agent** does all work in-session.
11. **Fork later.** A GitHub fork is created only after the feature is complete.
12. **Target macOS: develop on Sequoia, stay compatible with Tahoe** (decided 2026-10-23). Sam's dev machine runs macOS 15.7.9. `TerminalController.swift:20` picks the titlebar-tabs window by OS: macOS 26+ (built with Swift 6.2+) uses `TitlebarTabsTahoeTerminalWindow`, anything older (Sequoia included) uses `TitlebarTabsVenturaTerminalWindow`. So Sequoia work goes in the Ventura class, and the Tahoe class must at least compile and degrade to the dot fallback until it can be tested on macOS 26.

## Where the code goes

| Concern | File |
|---|---|
| Palette type, parsing, C sync, Zig tests | `src/config/tab_color.zig` (new) |
| Config keys and doc comments | `src/config/Config.zig` |
| C bridge for the palette list | `src/config/c_get.zig`, `include/ghostty.h` |
| Swift config accessors | `macos/Sources/Ghostty/Ghostty.Config.swift` |
| `TabColorStyle` resolver, right-click picker | `macos/Sources/Features/Terminal/TerminalTabColor.swift` |
| Tab painting, `DerivedConfig`, dot fallback | `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` |
| Config push before repaint | `macos/Sources/Features/Terminal/TerminalController.swift` |
| Titlebar tabs on Sequoia (primary) | `TitlebarTabsVenturaTerminalWindow.swift` (already reaches `NSTabButton` `_backgroundView` at line 227) |
| Titlebar tabs on Tahoe (compatible) | `TitlebarTabsTahoeTerminalWindow.swift` (SwiftUI-hosted tab bar; different painting path) |
| Swift unit tests (deferred) | `macos/Tests/Terminal/` |

## Build environment (Sam's Mac)

- Zig 0.16.0 via `brew link zig@0.16` (`/opt/homebrew/opt/zig@0.16/bin/zig`).
- SwiftLint, nushell and the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`) installed.
- Build core: `zig build`. Build app: `nu macos/build.nu` → `macos/build/Debug/Ghostty.app`.

## Checklist

### Wave 0: setup
- [x] Branch `colorful-tabs` created from `main`.
- [x] Zig 0.16.0 and build tools installed; core and app build.
- [x] Contract frozen in `docs/colorful-tabs-contract.md` (2026-10-16). Still untracked: not committed.
- [ ] GitHub fork: deferred until the feature is complete (decision 11).

### Wave 1: foundations
- [x] **Zig config:** 6 keys in `Config.zig`, palette type in `tab_color.zig`, C structs in `ghostty.h`, `c_get.zig` test (`9506f46`, `cd9efc3`).
- [x] **Swift config bridge:** accessors and `TabColorPaletteEntry` in `Ghostty.Config.swift`, palette and opacity in `DerivedConfig` (`cd9efc3`, tuple fix in `e2bff18`).
- [x] **Color resolver:** done (`3e6b093`). `TabColorStyle.resolve()` now:
  - [x] uses `tab-*-active`/`tab-*-inactive` with no palette set. A palette no longer acts as the default style; it only serves picked colors (contract §3).
  - [x] resolves a picked color through the `tab-color-palette` entry whose name matches the color name, ignoring case (e.g. `blue:bg=...`). With no match, it uses `displayColor`.
  - [x] dims unset inactive colors by 0.65, forces 4.5:1 foreground contrast under Increase Contrast, forces opacity 1.0 under Reduce Transparency, clamps opacity to [0.01, 1], and resolves dynamic colors against the window's `effectiveAppearance`.
  - [x] resolves per tab: `TerminalWindow.tabColorStyle` uses that window's `tabColor`, and `paintTabs()` resolves for each window in the group. `DerivedConfig` now carries the raw tab keys.
- [x] Review all three against the contract (done 2026-10-23). Fixed in `tab_color.zig`: out-of-bounds write in `syncValueC`, `bg`/`fg` now required, names must be alphanumeric, duplicate names overwrite in place; Zig tests never compiled before and now pass (parse, invalid input, C view, clone, equal, `c_get`). Config docs no longer mention unsupported `cell-background`/`cell-foreground`, and the opacity doc says it is shared. Opacity is clamped in the Swift resolver, not in Zig.
- [ ] Push. Committed; branch has no upstream. Deferred to the end (decision 11).

### Wave 2: tab rendering
- [ ] **Painting:** partly done (`7bd0efd`). `paintTabs()` paints `_backgroundView` / `NSTabButtonBackground` and repaints on becomeMain, resignKey, tab bar appear and `syncAppearance`. Missing:
  - [ ] title (foreground) color.
  - [ ] `tab-background-opacity` not applied when painting.
  - [ ] Sequoia titlebar tabs: verify painting in `TitlebarTabsVenturaTerminalWindow` separately from native tabs.
  - [ ] Tahoe titlebar tabs: keep `TitlebarTabsTahoeTerminalWindow` compiling and fall back to the dot until tested on macOS 26.
  - [ ] repaint on appearance change.
- [ ] **Palettes and fallback:** right-click swatches use configured palettes; keep saved/restored and undo tab colors working; detect unpaintable tabs (hidden titlebar, missing private views) and fall back to the dot.
- [ ] Review, resolve overlaps in `TerminalWindow.swift`, check every must-have against the code.
- [ ] Commit and push.

### Wave 3: verify on Sam's Mac
- [ ] On Sequoia, build and try each style: native, `tabs`, `transparent`, `hidden`; light and dark; Reduce Transparency and Increase Contrast on.
- [ ] Tahoe: confirm the app builds with Swift 6.2+ (Xcode 26); test on a macOS 26 machine or VM when one is available.
- [ ] Fix whatever is reported, one round per batch of feedback.
- [ ] Final commit and push.

### Later (not in scope yet)
- [ ] Swift unit tests for the resolver (decision 8).
- [ ] iTerm's `OSC 6` escape code to set the tab color from the shell (`src/terminal/osc.zig:972` currently ignores it).
- [ ] Linux (GTK) tab colors.
- [ ] Upstream PR. Ghostty's `AI_POLICY.md` requires disclosing AI help and that you understand every line.

## Risks

- Tab painting relies on private AppKit views (`NSTabButton`, `_backgroundView`). Ghostty already does this; the dot fallback covers a macOS update breaking it.
- Native tabs and titlebar tabs paint through different code paths, so each needs its own work.

## Notes

- Commit `9506f46`'s message lists six files, but it only adds `tab_color.zig`; the rest landed in `cd9efc3`.

## Resuming in a new session

Read this file and `docs/colorful-tabs-contract.md`, run `git log --oneline main..colorful-tabs`,
confirm state in 1-2 sentences, then wait for Sam's instruction before coding.

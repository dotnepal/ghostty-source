# macos-tabs-location plan

Branch: `feature/macos-tabs-location` (off `colorful-tabs`).

## Scope

- New config key `macos-tabs-location = top | bottom`, default `top`.
- `top` is today's native AppKit tab bar, unchanged.
- `bottom` hides the native bar and shows a mirror strip below the terminal.
  Native tabbing stays (one `NSWindow` per tab); the strip reads
  `tabGroup.windows`.
- Applies to new windows only. Never changes tab systems on a live window.

## Hooks found in the code

- `TerminalWindow.swift:149-151` sets `tabbingMode`.
- `TerminalWindow.swift:390-394` already loops over `tabGroup.windows` to paint
  tabs.
- `TerminalController.swift:45` already detects tab-order changes through a
  hash of `tabGroup.windows`.
- `TerminalViewContainer.swift` is the window's `contentView`; the bottom inset
  goes here.
- The titlebar title needs no work: each tab is its own window and already has
  its own title.

## Ground rules

- No test cases anywhere in the code changes (no Zig tests, no Swift tests).
  Testing is manual. Builds are run only to check that the code compiles.
- Main agent: Opus (medium effort). Subagents: Sonnet (medium effort).
- At most 5 subagents in total. Their status is listed after every wave.
- After each phase: commit, mark the task complete, move on.
- No force push, no `/loop`, no push at all unless asked.
- If stuck, stop immediately and ask Sam for direction.
- Every write is logged to `.claude-audit-trail.log` (Logfmt, gitignored).

## Phase 0: Setup (main)

1. Switch to `feature/macos-tabs-location`.
2. Write this plan file. Commit.

## Phase 1: Spike gate (main)

3. Add a minimal path that calls `toggleTabBar(_:)` on the window when the tab
   bar is visible. This tests the unverified assumption that AppKit keeps the
   tab group while the native bar is hidden.
4. Build (no tests). Commit.
5. Planned stop: Sam checks by hand that tabs still group and switch with
   ⌘1/⌘2 and Ctrl+Tab while the native bar is hidden. If it fails, stop and
   reconsider. This is the only intentional pause.

## Phase 2: Wave A, config (2 subagents in parallel)

- A1 (Zig): add `@"macos-tabs-location": MacTabsLocation = .top` and the
  `MacTabsLocation` enum (`top`, `bottom`) to `Config.zig`, following
  `macos-titlebar-style` (`Config.zig:3458`, enum at `:9416`). Docs with
  `Available since: 1.4.0`, noting it applies to new windows only. Expose it
  through the C config the same way `macos-titlebar-style` is.
- A2 (Swift): add the matching property and enum (with `default`) in
  `Ghostty.Config.swift`, mirroring `macosTitlebarStyle`.
- Main reviews both diffs, builds, commits.

## Phase 3: Wave B, view and window (2 subagents in parallel)

Main first defines the interface: `TabStripItem` (title, colours, isActive,
window ref).

- B1: new `TabStripView.swift`. A row of tab buttons plus a "+" button. Each
  button shows the title, the ⌘N hint and the active/inactive colour from a
  `TabColorStyle`. Exposes `update(items:)` and `onSelect` / `onNewTab`
  callbacks. No drag-reorder and no right-click picker in v1.
- B2: in `TerminalViewContainer.swift`, add the strip as a bottom subview and
  shrink the terminal's bottom constraint by the strip height, only in
  `bottom` mode. In `TerminalWindow.swift`, read `macosTabsLocation` into
  `DerivedConfig` at creation and hide the native bar using the Phase 1
  mechanism.
- Main reviews, builds, commits.

## Phase 4: Wave C, wiring (1 subagent)

- C1: drive `update(items:)` from `tabGroup.windows` whenever tabs are added,
  removed, reordered, retitled or recoloured. Reuse the tab-order hash at
  `TerminalController.swift:45` and the `tabGroup` loop at
  `TerminalWindow.swift:390`. Colours come from each window's
  `tabColorStyle`. `onSelect` sets `tabGroup.selectedWindow`. `onNewTab` calls
  the controller's existing new-tab path.
- Main reviews, builds, commits.

## Phase 5: Wrap-up (main)

- Update the docs and this plan file, add the audit trail entry, and review
  the full branch diff. The strip is hidden with one tab, following native
  behaviour. Commit.
- Final report: what changed, what is untested, known gaps (no reorder or
  right-click picker on the strip).

## Subagents

A1, A2, B1, B2, C1 (5 total, the limit).

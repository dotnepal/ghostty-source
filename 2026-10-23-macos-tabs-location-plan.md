# macos-tabs-location plan

Branch: `feature/macos-tabs-location` (off `colorful-tabs`).
Board: https://github.com/orgs/dotnepal/projects/2 (issues #4 to #9, repo
`dotnepal/ghostty-source`).

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
- No force push, no `/loop`.
- If stuck, stop immediately and ask Sam for direction. A failed build that
  cannot be fixed counts as stuck.
- Every write is logged to `.claude-audit-trail.log` (Logfmt, gitignored).

## Board workflow

The agent picks issues from Backlog and works through them autonomously, in
phase order, moving each issue along the board with `gh project item-edit`
(each move logged in the audit trail).

- Backlog -> Ready: the issue is ready to be picked up. The agent sets this
  itself and goes straight on.
- Ready -> In Progress: the agent has picked it up and started working.
- In Progress -> In Review: the task is complete, the changes are committed
  and pushed to the remote phase branch, and the PR is open.
- In Review -> Done: the agent has reviewed the PR (diff and build), all
  checks passed, and the PR is merged into `feature/macos-tabs-location`.
  Merging into `main` is not part of this plan.

## Branches and PRs

- Each phase gets its own branch off `feature/macos-tabs-location`, e.g.
  `feature/macos-tabs-location-phase-1`, pushed to `origin`
  (`dotnepal/ghostty-source`). Never `ghostty-org`.
- Each phase gets its own PR with base `feature/macos-tabs-location`.
- Phase 0 (#4) is already committed on the feature branch (`fa31fc99d`). Push
  the feature branch, then move #4 straight to Done without a PR.

## What "checks passed" means

- `zig build` succeeds.
- `nu macos/build.nu` succeeds (`xcodebuild`, Debug configuration).
- Any CI that runs on the PR is green.
- No automated tests are written or run.

## Runtime verification with AppleScript

The app exposes an AppleScript dictionary (`macos/Ghostty.sdef`, enabled by
`macos-applescript = true`). Use it to verify tab behaviour in the running
debug build instead of waiting for a manual check:

- `count tabs of window 1`, `selected tab of window 1`, `select tab`,
  `new tab`, `close tab`, `send key`.
- If a check fails (e.g. tabs ungroup), that counts as stuck: stop and ask.
- Known gap: the dictionary has no property for tab-bar visibility, so
  whether the native bar is actually hidden is not verified automatically.
  It is left for Sam's final manual check, and is noted in the issue and PR.

## Phase 0: Setup (#4, main)

1. Switch to `feature/macos-tabs-location`.
2. Write this plan file. Commit.

## Phase 1: Spike gate (#5, main)

3. Add a minimal path that calls `toggleTabBar(_:)` on the window when the tab
   bar is visible. This tests the assumption that AppKit keeps the tab group
   while the native bar is hidden.
4. Build with `zig build` and `nu macos/build.nu`. Commit.
5. Launch the debug build and verify with AppleScript: open two tabs, trigger
   the hide, check the tab count is still 2, then `select tab` and check the
   selected tab changes. Record the result in the issue and PR.
6. No stop for a manual check. If the AppleScript check fails, stop and ask.

## Phase 2: Wave A, config (#6, 2 subagents in parallel)

- A1 (Zig): add `@"macos-tabs-location": MacTabsLocation = .top` and the
  `MacTabsLocation` enum (`top`, `bottom`) to `Config.zig`, following
  `macos-titlebar-style` (`Config.zig:3458`, enum at `:9416`). Docs with
  `Available since: 1.4.0`, noting it applies to new windows only. Expose it
  through the C config the same way `macos-titlebar-style` is.
- A2 (Swift): add the matching property and enum (with `default`) in
  `Ghostty.Config.swift`, mirroring `macosTitlebarStyle`.
- Main reviews both diffs, builds, commits.

## Phase 3: Wave B, view and window (#7, 2 subagents in parallel)

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

## Phase 4: Wave C, wiring (#8, 1 subagent)

- C1: drive `update(items:)` from `tabGroup.windows` whenever tabs are added,
  removed, reordered, retitled or recoloured. Reuse the tab-order hash at
  `TerminalController.swift:45` and the `tabGroup` loop at
  `TerminalWindow.swift:390`. Colours come from each window's
  `tabColorStyle`. `onSelect` sets `tabGroup.selectedWindow`; `onNewTab` calls
  the controller's existing new-tab path.
- Main reviews, builds, commits. Re-run the AppleScript tab count and
  `select tab` checks in `bottom` mode as a regression check.

## Phase 5: Wrap-up (#9, main)

- Update the docs and this plan file, add the audit trail entry, and review
  the full branch diff. The strip stays hidden with a single tab, following
  native behaviour. Commit.
- Final report: what changed, what is untested, known gaps (no reorder or
  right-click picker on the strip, bar visibility not automatically
  verified).

## Subagents

A1, A2, B1, B2, C1 (5 total, the limit).

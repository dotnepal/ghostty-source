# Example: macOS Colorful Tabs

This contains an example configuration for coloring tabs on macOS: the
`tab-background-active`, `tab-foreground-active`, `tab-background-inactive`,
`tab-foreground-inactive`, `tab-background-opacity` and `tab-color-palette`
keys, and the right-click "Tab Color" picker they drive.

Unlike the other examples this is not a library project. There is nothing to
build, so there is no `build.zig`, and CI does not run it. The
[`config.ghostty`](config.ghostty) file documents every key, the order in
which colors are resolved, and what the macOS accessibility settings change.

## Usage

Try the configuration without touching your own, from the root of the
repository, with a Ghostty build that has colorful tabs:

```shell-session
ghostty --config-default-files=false --config-file=example/macos-colorful-tabs/config.ghostty
```

`--config-default-files=false` must be a command line flag. It does nothing
inside a configuration file. Without it, tab colors in your own configuration
mix with the ones in this example.

Open a few tabs with `Cmd+T` and right-click one to pick a color. After editing
the file, reload it with `Cmd+Shift+,`.

To use it for real, copy the keys you want into your configuration file.

## Notes

- macOS only. The keys have no effect on Linux (GTK).
- Tab colors are painted wherever macOS shows a tab bar. macOS hides the tab
  bar when a window has a single tab, so there is nothing to color then.
- If a tab can't be painted, for example because macOS changed its internal
  tab views, a small dot in the tab's color is shown instead.
- Tested on macOS 15 (Sequoia) with the `native`, `tabs`, `transparent` and
  `hidden` values of `macos-titlebar-style`. Not yet tested on macOS 26.

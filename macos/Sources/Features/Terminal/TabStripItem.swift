import AppKit

/// One tab as shown by `TabStripView`, the bottom tab strip used when
/// `macos-tabs-location = bottom`.
struct TabStripItem {
    /// The tab's window. Each native tab is its own window.
    weak var window: NSWindow?

    let title: String

    /// The keyboard shortcut hint, e.g. "⌘1". Nil when the tab has none.
    let shortcut: String?

    let isActive: Bool

    /// Resolved colors for this tab. Nil colors fall back to the system defaults.
    let style: TabColorStyle
}

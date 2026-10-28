import AppKit

/// The bottom tab strip used when `macos-tabs-location = bottom`. It draws one
/// button per native tab plus a "+" button, and reports clicks through closures.
///
/// The strip owns its height: with fewer than two tabs it collapses to zero
/// (like the native tab bar), so a neighbour anchored to its top anchor reflows.
final class TabStripView: NSView {
    static let height: CGFloat = 28

    /// Width of the trailing "+" button.
    private static let newTabButtonWidth: CGFloat = 32

    /// Called with the window of the tab that was clicked.
    var onSelect: ((NSWindow) -> Void)?

    /// Called when the "+" button is clicked.
    var onNewTab: (() -> Void)?

    /// Called on right-click with the window of the tab that was clicked. Returns
    /// the context menu to show, or nil for none.
    var onContextMenu: ((NSWindow) -> NSMenu?)?

    private let tabsStack = NSStackView()
    private let newTabButton = NSButton()
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

    private let titleFont: NSFont

    init(titleFont: NSFont = .systemFont(ofSize: NSFont.smallSystemFontSize)) {
        self.titleFont = titleFont
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        // The constraint is activated here so the strip always owns its height;
        // whoever adds the strip to a view only needs to position it.
        heightConstraint.isActive = true

        tabsStack.translatesAutoresizingMaskIntoConstraints = false
        tabsStack.orientation = .horizontal
        tabsStack.distribution = .fillEqually
        tabsStack.spacing = 0
        addSubview(tabsStack)

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.title = "+"
        newTabButton.font = .systemFont(ofSize: 16)
        newTabButton.isBordered = false
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        newTabButton.setAccessibilityLabel("New Tab")
        addSubview(newTabButton)

        NSLayoutConstraint.activate([
            tabsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabsStack.topAnchor.constraint(equalTo: topAnchor),
            tabsStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            tabsStack.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor),

            newTabButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            newTabButton.topAnchor.constraint(equalTo: topAnchor),
            newTabButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: Self.newTabButtonWidth),
        ])

        applyVisibility(itemCount: 0)
    }

    // MARK: Update

    /// Rebuild the strip from the given tabs. Safe to call repeatedly.
    func update(items: [TabStripItem]) {
        for view in tabsStack.arrangedSubviews {
            tabsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        applyVisibility(itemCount: items.count)
        guard items.count >= 2 else { return }

        for item in items {
            let tab = TabStripTabView(item: item, titleFont: titleFont)
            tab.onClick = { [weak self] window in
                self?.onSelect?(window)
            }
            tab.onContextMenu = { [weak self] window in
                self?.onContextMenu?(window)
            }
            tabsStack.addArrangedSubview(tab)
        }

        newTabButton.contentTintColor = .labelColor
    }

    /// Collapse the strip with a single tab, like the native tab bar.
    private func applyVisibility(itemCount: Int) {
        let visible = itemCount >= 2
        heightConstraint.constant = visible ? Self.height : 0
        tabsStack.isHidden = !visible
        newTabButton.isHidden = !visible
    }

    @objc private func newTabClicked() {
        onNewTab?()
    }
}

/// A single tab button inside `TabStripView`.
private final class TabStripTabView: NSView {
    var onClick: ((NSWindow) -> Void)?
    var onContextMenu: ((NSWindow) -> NSMenu?)?

    private let item: TabStripItem
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    init(item: TabStripItem, titleFont: NSFont) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        titleLabel.stringValue = item.title
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.font = titleFont
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        shortcutLabel.stringValue = item.shortcut ?? ""
        shortcutLabel.isHidden = item.shortcut == nil
        shortcutLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 2)
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(shortcutLabel)

        // The title is centered in the button; the shortcut hint sits at the
        // trailing edge and the title never runs underneath it.
        let centered = titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        centered.priority = .defaultHigh
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            centered,
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: item.shortcut == nil ? trailingAnchor : shortcutLabel.leadingAnchor,
                constant: item.shortcut == nil ? -8 : -4),

            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseDown(with event: NSEvent) {
        // Handled on mouseUp, but swallow the press so it doesn't fall through.
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), let window = item.window else { return }
        onClick?(window)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let window = item.window else { return nil }
        return onContextMenu?(window)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        let style = item.style
        let background: NSColor
        let foreground: NSColor
        let shortcutForeground: NSColor

        if item.isActive {
            background = style.activeBackground ?? .controlBackgroundColor
            foreground = style.activeForeground ?? .labelColor
            shortcutForeground = foreground
        } else {
            background = style.inactiveBackground ?? .controlBackgroundColor
            foreground = style.inactiveForeground ?? .secondaryLabelColor
            shortcutForeground = foreground
        }

        titleLabel.textColor = foreground
        shortcutLabel.textColor = shortcutForeground.withAlphaComponent(0.7)

        // Dynamic system colors resolve against the current appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let alpha = background.alphaComponent * CGFloat(style.backgroundOpacity)
            layer?.backgroundColor = background.withAlphaComponent(alpha).cgColor
        }
    }
}

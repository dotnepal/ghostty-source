import AppKit
import SwiftUI

enum TerminalTabColor: Int, CaseIterable, Codable {
    case none
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case teal
    case graphite

    var localizedName: String {
        switch self {
        case .none:
            return "None"
        case .blue:
            return "Blue"
        case .purple:
            return "Purple"
        case .pink:
            return "Pink"
        case .red:
            return "Red"
        case .orange:
            return "Orange"
        case .yellow:
            return "Yellow"
        case .green:
            return "Green"
        case .teal:
            return "Teal"
        case .graphite:
            return "Graphite"
        }
    }

    var displayColor: NSColor? {
        switch self {
        case .none:
            return nil
        case .blue:
            return .systemBlue
        case .purple:
            return .systemPurple
        case .pink:
            return .systemPink
        case .red:
            return .systemRed
        case .orange:
            return .systemOrange
        case .yellow:
            return .systemYellow
        case .green:
            return .systemGreen
        case .teal:
            if #available(macOS 13.0, *) {
                return .systemMint
            } else {
                return .systemTeal
            }
        case .graphite:
            return .systemGray
        }
    }

    func swatchImage(selected: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let circleRect = rect.insetBy(dx: 1, dy: 1)
            let circlePath = NSBezierPath(ovalIn: circleRect)

            if let fillColor = self.displayColor {
                fillColor.setFill()
                circlePath.fill()
            } else {
                NSColor.clear.setFill()
                circlePath.fill()
                NSColor.quaternaryLabelColor.setStroke()
                circlePath.lineWidth = 1
                circlePath.stroke()
            }

            if self == .none {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: circleRect.minX + 2, y: circleRect.minY + 2))
                slash.line(to: NSPoint(x: circleRect.maxX - 2, y: circleRect.maxY - 2))
                slash.lineWidth = 1.5
                NSColor.secondaryLabelColor.setStroke()
                slash.stroke()
            }

            if selected {
                let highlight = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                highlight.lineWidth = 2
                NSColor.controlAccentColor.setStroke()
                highlight.stroke()
            }

            return true
        }
    }
}

// MARK: - Menu View

/// A SwiftUI view displaying a color palette for tab color selection.
/// Used as a custom view inside an NSMenuItem in the tab context menu.
struct TabColorMenuView: View {
    @State private var currentSelection: TerminalTabColor
    let onSelect: (TerminalTabColor) -> Void

    init(selectedColor: TerminalTabColor, onSelect: @escaping (TerminalTabColor) -> Void) {
        self._currentSelection = State(initialValue: selectedColor)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Tab Color")
                .padding(.bottom, 2)

            ForEach(Self.paletteRows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { color in
                        TabColorSwatch(
                            color: color,
                            isSelected: color == currentSelection
                        ) {
                            currentSelection = color
                            onSelect(color)
                        }
                    }
                }
            }
        }
        .padding(.leading, Self.leadingPadding)
        .padding(.trailing, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    static let paletteRows: [[TerminalTabColor]] = [
        [.none, .blue, .purple, .pink, .red],
        [.orange, .yellow, .green, .teal, .graphite],
    ]

    /// Leading padding to align with the menu's icon gutter.
    /// macOS 26 introduced icons in menus, requiring additional padding.
    private static var leadingPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return 40
        } else {
            return 12
        }
    }
}

/// A single color swatch button in the tab color palette.
private struct TabColorSwatch: View {
    let color: TerminalTabColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if color == .none {
                    Image(systemName: isSelected ? "circle.slash" : "circle")
                        .foregroundStyle(.secondary)
                } else if let displayColor = color.displayColor {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.fill")
                        .foregroundStyle(Color(nsColor: displayColor))
                }
            }
            .font(.system(size: 16))
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(color.localizedName)
    }
}

// MARK: - Colored Tabs

/// Resolved tab color style derived from the Ghostty config and a tab's picked color.
/// Used to paint tab backgrounds and foregrounds. All colors are concrete sRGB colors
/// resolved against a specific appearance, so they don't change if the appearance does;
/// re-resolve when it changes.
struct TabColorStyle {
    let activeBackground: NSColor?
    let activeForeground: NSColor?
    let inactiveBackground: NSColor?
    let inactiveForeground: NSColor?

    /// Opacity applied to both active and inactive backgrounds.
    let backgroundOpacity: Double

    /// The default style — no tab coloring applied (Ghostty default behavior).
    static let `default` = TabColorStyle(
        activeBackground: nil,
        activeForeground: nil,
        inactiveBackground: nil,
        inactiveForeground: nil,
        backgroundOpacity: 1.0
    )

    /// The factor applied to active colors to derive unset inactive colors.
    static let inactiveDimFactor: CGFloat = 0.65

    /// The minimum foreground/background contrast ratio when Increase Contrast is on.
    static let minimumContrastRatio: Double = 4.5

    // swiftlint:disable function_parameter_count
    /// Resolve the tab color style for a single tab.
    ///
    /// Resolution order:
    /// 1. Picked color (right-click picker), through the `tab-color-palette` entry whose
    ///    name matches the color's name (case-insensitive). With no matching entry the
    ///    built-in system color is used.
    /// 2. tab-*-active / tab-*-inactive config keys
    /// 3. Ghostty default (no coloring)
    ///
    /// Unset inactive colors are the active colors dimmed by `inactiveDimFactor`. Then
    /// Reduce Transparency forces opacity to 1 and Increase Contrast forces each foreground
    /// to meet `minimumContrastRatio` against its background.
    static func resolve(
        palette: [Ghostty.Config.TabColorPaletteEntry],
        pickedColor: TerminalTabColor,
        bgActive: NSColor?,
        fgActive: NSColor?,
        bgInactive: NSColor?,
        fgInactive: NSColor?,
        bgOpacity: Double,
        appearance: NSAppearance,
        reduceTransparency: Bool,
        increaseContrast: Bool
    ) -> TabColorStyle {
        var activeBg: NSColor?
        var activeFg: NSColor?
        var inactiveBg: NSColor?
        var inactiveFg: NSColor?

        if pickedColor != .none {
            // Later palette entries with the same name overwrite earlier ones.
            let name = pickedColor.localizedName
            if let entry = palette.last(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                activeBg = entry.background
                activeFg = entry.foreground
                inactiveBg = entry.inactiveBackground
                inactiveFg = entry.inactiveForeground
            } else {
                activeBg = pickedColor.displayColor
                activeFg = fgActive
                inactiveFg = fgInactive
            }
        } else {
            activeBg = bgActive
            activeFg = fgActive
            inactiveBg = bgInactive
            inactiveFg = fgInactive
        }

        // Nothing configured: keep Ghostty's existing tab look.
        if activeBg == nil, activeFg == nil, inactiveBg == nil, inactiveFg == nil {
            return .default
        }

        // System colors are dynamic, so pin everything to the tab's appearance
        // before deriving anything from it.
        activeBg = activeBg?.resolved(in: appearance)
        activeFg = activeFg?.resolved(in: appearance)
        inactiveBg = inactiveBg?.resolved(in: appearance) ?? activeBg?.dimmed(by: inactiveDimFactor)
        inactiveFg = inactiveFg?.resolved(in: appearance) ?? activeFg?.dimmed(by: inactiveDimFactor)

        if increaseContrast {
            activeFg = contrastingForeground(activeFg, on: activeBg, appearance: appearance)
            inactiveFg = contrastingForeground(inactiveFg, on: inactiveBg, appearance: appearance)
        }

        return TabColorStyle(
            activeBackground: activeBg,
            activeForeground: activeFg,
            inactiveBackground: inactiveBg,
            inactiveForeground: inactiveFg,
            backgroundOpacity: reduceTransparency ? 1.0 : min(max(bgOpacity, 0.01), 1.0)
        )
    }
    // swiftlint:enable function_parameter_count

    /// Returns `fg` if it meets `minimumContrastRatio` against `bg`, otherwise black or
    /// white, whichever contrasts more. A nil `fg` stands for the system label color.
    /// With no `bg` there is nothing to contrast against, so `fg` is returned unchanged.
    private static func contrastingForeground(
        _ fg: NSColor?,
        on bg: NSColor?,
        appearance: NSAppearance
    ) -> NSColor? {
        guard let bg else { return fg }
        let effectiveFg = fg ?? NSColor.labelColor.resolved(in: appearance)
        if effectiveFg.contrastRatio(with: bg) >= minimumContrastRatio { return fg }
        return NSColor.black.contrastRatio(with: bg) >= NSColor.white.contrastRatio(with: bg)
            ? .black
            : .white
    }
}

private extension NSColor {
    /// This color as a concrete sRGB color, resolving dynamic (system) colors in `appearance`.
    func resolved(in appearance: NSAppearance) -> NSColor {
        var result = self
        appearance.performAsCurrentDrawingAppearance {
            result = self.usingColorSpace(.sRGB) ?? self
        }
        return result
    }

    /// This color with its RGB components scaled by `factor`. Alpha is kept.
    func dimmed(by factor: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return self }
        return NSColor(
            srgbRed: rgb.redComponent * factor,
            green: rgb.greenComponent * factor,
            blue: rgb.blueComponent * factor,
            alpha: rgb.alphaComponent
        )
    }

    /// WCAG 2 relative luminance.
    var relativeLuminance: Double {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        func linear(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent)
            + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }

    /// WCAG 2 contrast ratio between this color and `other`, from 1 to 21.
    func contrastRatio(with other: NSColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

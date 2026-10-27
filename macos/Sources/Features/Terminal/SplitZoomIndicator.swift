import SwiftUI

struct SplitZoomIndicator: View {
    let isZoomed: Bool
    let imagePath: String?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isZoomed {
                badge
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.easeInOut(duration: 0.2), value: isZoomed)
        .allowsHitTesting(false)
    }

    private var badge: some View {
        icon
            .frame(width: 28, height: 28)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
            .accessibilityLabel("Split is zoomed")
    }

    @ViewBuilder
    private var icon: some View {
        if let image = loadImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private func loadImage() -> NSImage? {
        guard let imagePath else { return nil }
        let key = imagePath as NSString
        if let cached = Self.cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOfFile: imagePath) else { return nil }
        Self.cache.setObject(image, forKey: key)
        return image
    }
}

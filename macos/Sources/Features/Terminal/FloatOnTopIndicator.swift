import SwiftUI

/// A short-lived message shown when a window starts or stops floating on top.
/// Each toast has its own identity so a new one replaces the previous one.
struct FloatOnTopToast: Equatable {
    let id = UUID()
    let isOn: Bool
}

/// Shows that a window floats on top of other windows: a pin badge while it does, and
/// a brief message when the state changes. Display only; it never takes mouse events.
struct FloatOnTopIndicator: View {
    let isFloating: Bool
    let toast: FloatOnTopToast?

    var body: some View {
        ZStack(alignment: .top) {
            if isFloating {
                HStack {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(7)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                        .accessibilityLabel("Window floats on top")
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.leading, 10)
                .transition(.opacity)
            }

            if let toast {
                HStack(spacing: 6) {
                    Image(systemName: toast.isOn ? "pin.fill" : "pin.slash")
                    Text(toast.isOn ? "Float on top: On" : "Float on top: Off")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                .padding(.top, 10)
                .transition(.opacity)
                .id(toast.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isFloating)
        .animation(.easeInOut(duration: 0.2), value: toast)
        .allowsHitTesting(false)
    }
}

import SwiftUI

struct TabDropOverlayView: View {
    let showOverlay: Bool
    let isTarget: Bool
    let highlightLeft: Bool
    let highlightRight: Bool

    var body: some View {
        if showOverlay {
            GeometryReader { geometry in
                let halfWidth = max(geometry.size.width / 2, 1)
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fillColor(isHighlighted: highlightLeft))
                        .frame(width: halfWidth)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fillColor(isHighlighted: highlightRight))
                        .frame(width: halfWidth)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isTarget ? Color.accentColor.opacity(0.9) : Color.accentColor.opacity(0.2),
                            lineWidth: isTarget ? 2 : 1
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func fillColor(isHighlighted: Bool) -> Color {
        if isHighlighted {
            return Color.accentColor.opacity(0.28)
        }
        if isTarget {
            return Color.accentColor.opacity(0.12)
        }
        return Color.clear
    }
}

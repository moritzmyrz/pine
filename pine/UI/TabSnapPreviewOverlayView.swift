import AppKit
import SwiftUI

struct TabSnapPreviewOverlayView: View {
    let hoveredSide: SplitDropSide
    let draggedTab: Tab?
    let anchorTab: Tab?

    var body: some View {
        GeometryReader { geometry in
            if hoveredSide != .none {
                Group {
                    if hoveredSide == .top || hoveredSide == .bottom {
                        VStack(spacing: 10) {
                            if hoveredSide == .top {
                                panePreview(tab: draggedTab, emphasized: true)
                                panePreview(tab: anchorTab, emphasized: false)
                            } else {
                                panePreview(tab: anchorTab, emphasized: false)
                                panePreview(tab: draggedTab, emphasized: true)
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            if hoveredSide == .left {
                                panePreview(tab: draggedTab, emphasized: true)
                                panePreview(tab: anchorTab, emphasized: false)
                            } else {
                                panePreview(tab: anchorTab, emphasized: false)
                                panePreview(tab: draggedTab, emphasized: true)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(Color.black.opacity(0.08))
                .transition(.opacity)
                .animation(.easeOut(duration: 0.16), value: hoveredSide)
            }
        }
        .allowsHitTesting(false)
    }

    private func panePreview(tab: Tab?, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let favicon = faviconImage(for: tab) {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                }
                Text(tab?.title ?? "Tab Preview")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: emphasized
                            ? [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.2)]
                            : [Color.gray.opacity(0.22), Color.gray.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            emphasized ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.25),
                            lineWidth: emphasized ? 2 : 1
                        )
                }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func faviconImage(for tab: Tab?) -> NSImage? {
        guard let data = tab?.faviconData else { return nil }
        return NSImage(data: data)
    }
}

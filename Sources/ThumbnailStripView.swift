import SwiftUI

/// Uniform gap between thumbnails, and the inset around the whole strip, so
/// the spacing reads as one consistent rhythm top to bottom.
private let stripGap: CGFloat = 8

struct ThumbnailStripView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: stripGap) {
                    ForEach(Array(appState.items.enumerated()), id: \.element.id) { index, item in
                        ThumbnailStripRow(
                            item: item,
                            isCurrent: index == appState.currentIndex,
                            decision: appState.decisions[item.id]
                        )
                        .id(item.id)
                        .onTapGesture {
                            appState.jumpTo(item)
                        }
                    }
                }
                .padding(stripGap)
            }
            .onChange(of: appState.currentIndex) { _, newIndex in
                guard appState.items.indices.contains(newIndex) else { return }
                withAnimation {
                    proxy.scrollTo(appState.items[newIndex].id, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
    }
}

/// One row: full strip width, height derived from the image's own aspect
/// ratio (Google Photos style, stacked vertically). The ratio comes from
/// image metadata rather than the decoded thumbnail so the row is already the
/// right height before the picture arrives, and scrolling doesn't reflow.
private struct ThumbnailStripRow: View {
    let item: ImageItem
    let isCurrent: Bool
    let decision: Decision?

    @State private var thumbnail: NSImage?
    @State private var aspectRatio: CGFloat

    init(item: ImageItem, isCurrent: Bool, decision: Decision?) {
        self.item = item
        self.isCurrent = isCurrent
        self.decision = decision
        _aspectRatio = State(initialValue: ThumbnailCache.shared.cachedAspectRatio(for: item.url) ?? 4.0 / 3.0)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(white: 0.25)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            if let decision = decision {
                Image(systemName: decision == .pick ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(.white, decision == .pick ? Color.green : Color.red)
                    .font(.system(size: 16))
                    .padding(4)
            }
        }
        .onAppear {
            ThumbnailCache.shared.aspectRatio(for: item.url) { ratio in
                aspectRatio = ratio
            }
            ThumbnailCache.shared.thumbnail(for: item.url) { loaded in
                thumbnail = loaded
            }
        }
    }
}

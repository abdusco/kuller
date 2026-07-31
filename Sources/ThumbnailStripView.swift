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
                            decision: appState.decisions[item.id],
                            cropRect: appState.cropRects[item.id],
                            onDelete: { appState.removeVirtualCopy(item) }
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
    let cropRect: NormalizedRect?
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?
    @State private var aspectRatio: CGFloat

    init(item: ImageItem, isCurrent: Bool, decision: Decision?, cropRect: NormalizedRect?, onDelete: @escaping () -> Void) {
        self.item = item
        self.isCurrent = isCurrent
        self.decision = decision
        self.cropRect = cropRect
        self.onDelete = onDelete
        let fullAspect = ThumbnailCache.shared.cachedAspectRatio(for: item.url) ?? 4.0 / 3.0
        if let cropRect, cropRect != .fullImage, cropRect.height > 0 {
            _aspectRatio = State(initialValue: fullAspect * cropRect.width / cropRect.height)
        } else {
            _aspectRatio = State(initialValue: fullAspect)
        }
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

            if item.isVirtualCopy {
                // Crop badge and delete button sit in the two bottom
                // corners so neither ever competes with the decision
                // indicator, which always stays top-trailing regardless of
                // whether this row is a virtual copy.
                cropBadge
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            if let decision = decision {
                Image(systemName: decision == .pick ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(.white, decision == .pick ? Color.green : Color.red)
                    .font(.system(size: 16))
                    .padding(4)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: cropRect) { _, _ in refresh() }
    }

    private var cropBadge: some View {
        Image(systemName: "crop")
            .foregroundStyle(.white)
            .font(.system(size: 11, weight: .semibold))
            .padding(3)
            .background(Circle().fill(Color.black.opacity(0.55)))
    }

    /// Re-fetches (from cache — cheap) and re-crops, so committing a crop
    /// while this row is already on screen updates it without needing the
    /// row itself to be recreated.
    private func refresh() {
        ThumbnailCache.shared.aspectRatio(for: item.url) { ratio in
            if let cropRect, cropRect != .fullImage, cropRect.height > 0 {
                aspectRatio = ratio * cropRect.width / cropRect.height
            } else {
                aspectRatio = ratio
            }
        }
        ThumbnailCache.shared.thumbnail(for: item.url) { loaded in
            thumbnail = loaded?.cropped(to: cropRect)
        }
    }
}

import SwiftUI

struct ThumbnailStripView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
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
                .padding(6)
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

private struct ThumbnailStripRow: View {
    let item: ImageItem
    let isCurrent: Bool
    let decision: Decision?

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color(white: 0.25)
                }
            }
            .frame(width: 104, height: 78)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            if let decision = decision {
                Image(systemName: decision == .pick ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(.white, decision == .pick ? Color.green : Color.red)
                    .font(.system(size: 16))
                    .padding(2)
            }
        }
        .padding(4)
        .onAppear {
            ThumbnailCache.shared.thumbnail(for: item.url) { loaded in
                thumbnail = loaded
            }
        }
    }
}

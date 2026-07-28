import SwiftUI

struct PicksColumnView: View {
    let picks: [ImageItem]

    var body: some View {
        VStack(spacing: 0) {
            Text("Picks (\(picks.count))")
                .font(.headline)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(picks) { item in
                        PicksThumbnail(item: item)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 160)
        .background(Color(white: 0.16))
    }
}

private struct PicksThumbnail: View {
    let item: ImageItem
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color(white: 0.25)
            }
        }
        .frame(width: 144, height: 108)
        .clipped()
        .cornerRadius(4)
        .onAppear {
            ThumbnailCache.shared.thumbnail(for: item.url) { loaded in
                thumbnail = loaded
            }
        }
    }
}

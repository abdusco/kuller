import SwiftUI

/// The image window IS the image: the window's size and aspect ratio track
/// the current image, so this view just fills it. Moving and resizing are
/// handled at the AppKit level by HoverTrackingHostingView (native window
/// drag + pinch), not by SwiftUI gestures.
struct ImageViewerView: View {
    let item: ImageItem?

    @State private var image: NSImage?
    @State private var loadedURL: URL?

    var body: some View {
        ZStack {
            // No backdrop: the window is sized to the image's aspect ratio,
            // so the image fills it edge to edge and anything behind the
            // window shows through around it.
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear { load(item) }
        .onChange(of: item) { _, newItem in
            load(newItem)
        }
    }

    private func load(_ item: ImageItem?) {
        guard let item = item else {
            image = nil
            loadedURL = nil
            return
        }
        loadedURL = item.url
        ThumbnailCache.shared.fullImage(for: item.url) { loaded in
            guard loadedURL == item.url else { return }
            image = loaded
            if let size = loaded?.size, size.width > 0, size.height > 0 {
                resizeCanvasWindow(toImageSize: size)
            }
        }
    }
}

import SwiftUI

/// The image window IS the image: the window's size and aspect ratio track
/// the current image, so this view just fills it. Moving and resizing are
/// handled at the AppKit level by HoverTrackingHostingView (native window
/// drag + pinch), not by SwiftUI gestures.
struct ImageViewerView: View {
    let item: ImageItem?
    /// While cropping, pins the image to this exact size (computed by
    /// CropSession to leave padding on all sides within the now
    /// screen-covering window) instead of letting aspect-fit fill whatever
    /// space is available.
    var pinnedSize: CGSize?
    /// The committed crop for `item`, applied to the displayed/loaded image
    /// (and the window size it's derived from) so the culling view itself
    /// reflects a crop, not just the thumbnails. Passed as `nil` while
    /// actively cropping — the crop overlay needs the untouched full image.
    var cropRect: NormalizedRect?

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
        .frame(maxWidth: pinnedSize == nil ? .infinity : nil, maxHeight: pinnedSize == nil ? .infinity : nil)
        .frame(width: pinnedSize?.width, height: pinnedSize?.height)
        .contentShape(Rectangle())
        .onAppear { load(item) }
        .onChange(of: item) { _, newItem in
            load(newItem)
        }
        .onChange(of: cropRect) { _, _ in
            load(item)
        }
    }

    private func load(_ item: ImageItem?) {
        guard let item = item else {
            image = nil
            loadedURL = nil
            return
        }
        loadedURL = item.url
        let cropRect = self.cropRect
        ThumbnailCache.shared.fullImage(for: item.url) { loaded in
            guard loadedURL == item.url else { return }
            let displayed = loaded?.cropped(to: cropRect)
            image = displayed
            if let size = displayed?.size, size.width > 0, size.height > 0 {
                resizeCanvasWindow(toImageSize: size)
            }
        }
    }
}

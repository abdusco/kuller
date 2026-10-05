import SwiftUI

/// The window follows the image's size until it reaches the display edges,
/// then this view clips the zoomed image within the window. Moving and resizing are
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
    var zoomedSize: CGSize?
    var zoomOffset: CGSize = .zero
    var imageCache: ThumbnailCache = .shared

    @State private var image: NSImage?
    @State private var loadID = UUID()

    var body: some View {
        GeometryReader { geometry in
            // No backdrop: the window is sized to the image's aspect ratio,
            // so the image fills it edge to edge and anything behind the
            // window shows through around it.
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: zoomedSize?.width ?? geometry.size.width,
                           height: zoomedSize?.height ?? geometry.size.height)
                    .position(x: geometry.size.width / 2 + zoomOffset.width,
                              y: geometry.size.height / 2 + zoomOffset.height)
            } else {
                ProgressView()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .frame(maxWidth: pinnedSize == nil ? .infinity : nil, maxHeight: pinnedSize == nil ? .infinity : nil)
        .frame(width: pinnedSize?.width, height: pinnedSize?.height)
        .clipped()
        .contentShape(Rectangle())
        .onAppear { load(item) }
        .onChange(of: item) { _, newItem in
            load(newItem)
        }
        .onChange(of: cropRect) { _, _ in
            load(item)
        }
        .onDisappear { loadID = UUID() }
    }

    private func load(_ item: ImageItem?) {
        let requestID = UUID()
        loadID = requestID
        guard let item = item else {
            image = nil
            return
        }
        let cropRect = self.cropRect
        // Size the window from source metadata before either preview arrives.
        // Upgrading the pixels must not resize the window or reset a zoom/pan
        // the user started while looking at the thumbnail.
        var sizedFromMetadata = false
        if var size = ThumbnailCache.quickPixelSize(of: item.url), size.width > 0, size.height > 0 {
            if let cropRect, cropRect.width > 0, cropRect.height > 0 {
                size.width *= cropRect.width
                size.height *= cropRect.height
            }
            resizeCanvasWindow(toImageSize: size)
            sizedFromMetadata = true
        }
        image = imageCache.cachedThumbnail(for: item.url)?.cropped(to: cropRect)
        // Both callbacks run on the main queue. A late thumbnail must never
        // replace the larger preview, even when that preview was cached.
        var fullImageLoaded = false
        imageCache.thumbnail(for: item.url) { loaded in
            guard loadID == requestID, !fullImageLoaded else { return }
            image = loaded?.cropped(to: cropRect)
        }
        imageCache.fullImage(for: item.url) { loaded in
            // Virtual copies share a URL, and navigating away and back can
            // leave several requests for that URL in flight.
            guard loadID == requestID else { return }
            guard let loaded else { return }
            fullImageLoaded = true
            let displayed = loaded.cropped(to: cropRect)
            image = displayed
            let size = displayed.size
            if !sizedFromMetadata, size.width > 0, size.height > 0 {
                resizeCanvasWindow(toImageSize: size)
            }
        }
    }
}

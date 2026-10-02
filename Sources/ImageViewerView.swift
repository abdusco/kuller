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
        ThumbnailCache.shared.fullImage(for: item.url) { loaded in
            // Virtual copies share a URL, and navigating away and back can
            // leave several requests for that URL in flight.
            guard loadID == requestID else { return }
            let displayed = loaded?.cropped(to: cropRect)
            image = displayed
            if let size = displayed?.size, size.width > 0, size.height > 0 {
                resizeCanvasWindow(toImageSize: size)
            }
        }
    }
}

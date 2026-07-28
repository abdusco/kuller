import SwiftUI

struct ImageViewerView: View {
    let item: ImageItem?

    @State private var image: NSImage?
    @State private var imageSize: CGSize = .zero
    @State private var zoomScale: CGFloat = 1.0
    @State private var gestureZoom: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var loadedURL: URL?

    /// Minimum sliver (in points) of the image that must always stay on
    /// screen, so a fully-panned-off image is never unreachable.
    private let minimumVisibleSliver: CGFloat = 48

    var body: some View {
        GeometryReader { geometry in
            let viewerSize = geometry.size
            ZStack {
                Color.black.opacity(0.2)

                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale * gestureZoom)
                        .offset(x: panOffset.width, y: panOffset.height)
                        .gesture(magnificationGesture(viewerSize: viewerSize))
                        .gesture(dragGesture(viewerSize: viewerSize))
                        .onTapGesture(count: 2) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                zoomScale = 1.0
                                gestureZoom = 1.0
                                panOffset = .zero
                                dragStart = .zero
                            }
                        }
                } else {
                    ProgressView()
                }
            }
            .frame(width: viewerSize.width, height: viewerSize.height)
            .clipped()
            .contentShape(Rectangle())
        }
        .onAppear { load(item) }
        .onChange(of: item) { _, newItem in
            zoomScale = 1.0
            gestureZoom = 1.0
            panOffset = .zero
            dragStart = .zero
            load(newItem)
        }
    }

    private func magnificationGesture(viewerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                gestureZoom = value
            }
            .onEnded { value in
                let newScale = max(0.2, min(zoomScale * value, 20))
                zoomScale = newScale
                gestureZoom = 1.0
                panOffset = clampedOffset(panOffset, zoom: newScale, viewerSize: viewerSize)
                dragStart = panOffset
            }
    }

    private func dragGesture(viewerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height
                )
                panOffset = clampedOffset(proposed, zoom: zoomScale, viewerSize: viewerSize)
            }
            .onEnded { _ in
                dragStart = panOffset
            }
    }

    /// The image's fit-to-window size at zoom 1.0, preserving aspect ratio.
    private func fitSize(for viewerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              viewerSize.width > 0, viewerSize.height > 0 else {
            return viewerSize
        }
        let imageAspect = imageSize.width / imageSize.height
        let viewerAspect = viewerSize.width / viewerSize.height
        if imageAspect > viewerAspect {
            return CGSize(width: viewerSize.width, height: viewerSize.width / imageAspect)
        } else {
            return CGSize(width: viewerSize.height * imageAspect, height: viewerSize.height)
        }
    }

    /// Clamps a proposed pan offset so at least `minimumVisibleSliver` points
    /// of the (possibly zoomed) image remain inside the viewer bounds.
    private func clampedOffset(_ proposed: CGSize, zoom: CGFloat, viewerSize: CGSize) -> CGSize {
        let fit = fitSize(for: viewerSize)
        let displaySize = CGSize(width: fit.width * zoom, height: fit.height * zoom)
        let maxX = max(0, viewerSize.width / 2 + displaySize.width / 2 - minimumVisibleSliver)
        let maxY = max(0, viewerSize.height / 2 + displaySize.height / 2 - minimumVisibleSliver)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func load(_ item: ImageItem?) {
        guard let item = item else {
            image = nil
            imageSize = .zero
            loadedURL = nil
            return
        }
        loadedURL = item.url
        ThumbnailCache.shared.fullImage(for: item.url) { loaded in
            guard loadedURL == item.url else { return }
            image = loaded
            imageSize = loaded?.size ?? .zero
        }
    }
}

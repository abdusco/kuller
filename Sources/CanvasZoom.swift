import CoreGraphics

/// The image keeps its aspect ratio; the window stops growing independently
/// on each axis when it reaches the display's usable bounds.
func zoomedCanvasFrame(imageSize: CGSize, around frame: CGRect, within screen: CGRect) -> CGRect {
    let size = CGSize(width: min(imageSize.width, screen.width),
                      height: min(imageSize.height, screen.height))
    return CGRect(
        x: min(max(frame.midX - size.width / 2, screen.minX), screen.maxX - size.width),
        y: min(max(frame.midY - size.height / 2, screen.minY), screen.maxY - size.height),
        width: size.width,
        height: size.height
    )
}

func clampedImageOffset(_ offset: CGSize, imageSize: CGSize, viewport: CGSize) -> CGSize {
    let maxX = max(0, (imageSize.width - viewport.width) / 2)
    let maxY = max(0, (imageSize.height - viewport.height) / 2)
    return CGSize(width: min(max(offset.width, -maxX), maxX),
                  height: min(max(offset.height, -maxY), maxY))
}

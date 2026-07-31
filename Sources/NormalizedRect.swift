import CoreGraphics
import AppKit

/// A crop rect normalized to an image's own bounds (0...1), bottom-left
/// origin — matching this app's existing AppKit-native coordinate
/// convention (canvasWindow.frame etc. are already bottom-left origin).
/// A future pixel-export implementation will need to flip Y, since
/// CGImage/ImageIO are top-left origin.
struct NormalizedRect: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let fullImage = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
}

extension NSImage {
    /// Crops to the sub-rectangle described by `rect` (fractions of this
    /// image's own bounds, bottom-left origin — same convention `draw(in:from:)`
    /// already uses, so no flip is needed). Used by thumbnail previews to
    /// reflect a committed crop without an actual export pipeline. Returns
    /// `self` unmodified for `nil`/full-image rects so uncropped images incur
    /// no extra copy.
    func cropped(to rect: NormalizedRect?) -> NSImage {
        guard let rect, rect != .fullImage, rect.width > 0, rect.height > 0 else { return self }
        let sourceRect = NSRect(
            x: rect.x * size.width,
            y: rect.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
        guard sourceRect.width > 0, sourceRect.height > 0 else { return self }
        let result = NSImage(size: sourceRect.size)
        result.lockFocus()
        draw(
            in: NSRect(origin: .zero, size: sourceRect.size),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }
}

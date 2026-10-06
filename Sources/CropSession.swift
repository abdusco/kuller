import CoreGraphics
import Combine

/// Transient, uncommitted state for one crop attempt. Owned by CullingView
/// as a @StateObject — unlike AppState.cropRects (the committed store), this
/// never needs to survive a cancel, so it lives entirely outside AppState.
final class CropSession: ObservableObject {
    @Published var rect: NormalizedRect?
    @Published var aspectRatio: CropAspectRatio = .original
    private(set) var imageAspect: CGFloat = 1
    /// The image's fixed on-screen size while cropping: the largest size at
    /// `imageAspect` that fits within `availableSize` inset by
    /// `CropMetrics.screenPadding` on every side. ImageViewerView pins the
    /// image to this exact size (rather than letting SwiftUI's aspect-fit
    /// re-derive it from the full-screen window, which would only ever
    /// letterbox one axis, never both at once) — so the crop window's own
    /// screen-covering size guarantees real padding on all four sides.
    private(set) var pinnedImageSize: CGSize = .zero

    /// Starts (or restarts) a crop attempt. Defaults to the full image when
    /// nothing was committed before — matches Photos.app/Lightroom, and
    /// means an untouched Return commits "no crop" rather than stranding the
    /// user on a fully-dimmed screen with no rect to work with.
    ///
    /// `aspectRatio` deliberately isn't reset here — it carries over from
    /// the previous crop (across images and across cancel/commit), matching
    /// the request to remember the last ratio used. Starting fresh (no
    /// `committedRect`) reshapes the full-image rect to that remembered
    /// ratio right away, rather than showing "full image" while the
    /// toolbar claims a different ratio is selected.
    func begin(committedRect: NormalizedRect?, imageAspect: CGFloat, availableSize: CGSize) {
        self.imageAspect = imageAspect
        self.rect = committedRect ?? .fullImage
        self.pinnedImageSize = CropSession.fitted(
            aspect: imageAspect,
            within: CGSize(
                width: max(availableSize.width - 2 * CropMetrics.screenPadding, 1),
                height: max(availableSize.height - 2 * CropMetrics.screenPadding, 1)
            )
        )
        if committedRect == nil {
            setAspectRatio(aspectRatio)
        }
    }

    private static func fitted(aspect: CGFloat, within size: CGSize) -> CGSize {
        let containerAspect = size.width / size.height
        if aspect > containerAspect {
            return CGSize(width: size.width, height: size.width / aspect)
        } else {
            return CGSize(width: size.height * aspect, height: size.height)
        }
    }

    /// The current aspect ratio's target, converted into *normalized*-space
    /// width/height units. The rect is stored as fractions of the image's
    /// own width and height, which aren't equal on screen (they preserve
    /// `imageAspect`), so a real target ratio R only produces an on-screen
    /// crop of ratio R once divided by `imageAspect` here — comparing R
    /// directly against normalized width/height (as if that space were
    /// square) silently distorts the crop and, worse, can push a
    /// ratio-locked edge/corner resize outside the image once the
    /// distorted "fits within 1" check kicks in.
    var normalizedTargetRatio: CGFloat? {
        guard let real = aspectRatio.widthToHeight(imageAspect: imageAspect) else { return nil }
        return real / imageAspect
    }

    /// Reshapes the current rect to the new ratio, keeping whichever of its
    /// two on-screen edges is currently longer at that same length (rather
    /// than always shrinking to fit inside the old box) — so cycling
    /// through ratios doesn't ratchet the crop area smaller and smaller.
    /// The comparison and the resulting size have to happen in real,
    /// on-screen units (via `pinnedImageSize`), not raw normalized
    /// fractions, since the two normalized axes aren't equal-scale (see
    /// `normalizedTargetRatio`) — "longer edge" is a screen concept.
    func setAspectRatio(_ newRatio: CropAspectRatio) {
        aspectRatio = newRatio
        guard let current = rect, let realRatio = newRatio.widthToHeight(imageAspect: imageAspect) else { return }
        rect = CropSession.resized(current, keepingLongestEdgeAtRealRatio: realRatio, pinnedImageSize: pinnedImageSize)
    }

    /// From a named ratio, cycles forward/backward as usual. But a
    /// freehand-drawn rect was never assigned any named ratio, so the first
    /// cycle press from `.free` would otherwise jump to whatever's next
    /// after `.free` in declaration order — visually unrelated to the shape
    /// on screen. Instead, that first press snaps to whichever named ratio
    /// the current rect already most resembles, and only subsequent presses
    /// actually step forward/backward from there.
    func cycleAspectRatio(forward: Bool, presets: [CropAspectRatio] = CropAspectRatio.allCases) {
        if aspectRatio == .free, let current = rect, current.height > 0, pinnedImageSize.height > 0 {
            let realRatio = (current.width * pinnedImageSize.width) / (current.height * pinnedImageSize.height)
            setAspectRatio(CropSession.nearestAspectRatio(toRealRatio: realRatio, imageAspect: imageAspect, presets: presets))
            return
        }
        setAspectRatio(aspectRatio.cycled(forward: forward, cases: presets))
    }

    private static func nearestAspectRatio(toRealRatio realRatio: CGFloat, imageAspect: CGFloat, presets: [CropAspectRatio]) -> CropAspectRatio {
        presets
            .filter { $0 != .free }
            .min { a, b in
                abs((a.widthToHeight(imageAspect: imageAspect) ?? 0) - realRatio)
                    < abs((b.widthToHeight(imageAspect: imageAspect) ?? 0) - realRatio)
            } ?? .original
    }

    /// Keeps `box`'s longer real-space edge the same length, derives the
    /// other edge from `ratio`, re-centers on `box`'s old center, then
    /// shrinks (preserving `ratio`) and re-clamps only if that overshoots
    /// the image bounds.
    private static func resized(
        _ box: NormalizedRect,
        keepingLongestEdgeAtRealRatio ratio: CGFloat,
        pinnedImageSize: CGSize
    ) -> NormalizedRect {
        guard pinnedImageSize.width > 0, pinnedImageSize.height > 0 else { return box }

        let realWidth = box.width * pinnedImageSize.width
        let realHeight = box.height * pinnedImageSize.height
        var newRealWidth: CGFloat
        var newRealHeight: CGFloat
        if realWidth >= realHeight {
            newRealWidth = realWidth
            newRealHeight = realWidth / ratio
        } else {
            newRealHeight = realHeight
            newRealWidth = realHeight * ratio
        }

        var width = newRealWidth / pinnedImageSize.width
        var height = newRealHeight / pinnedImageSize.height
        if width > 1 {
            height *= 1 / width
            width = 1
        }
        if height > 1 {
            width *= 1 / height
            height = 1
        }

        let centerX = box.x + box.width / 2
        let centerY = box.y + box.height / 2
        let x = min(max(centerX - width / 2, 0), 1 - width)
        let y = min(max(centerY - height / 2, 0), 1 - height)
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }
}

/// The area within the overlay's bounds where the image itself is actually
/// rendered: `pinnedSize`, centered — matching how ImageViewerView pins and
/// centers the image while cropping (see CropSession.pinnedImageSize).
func cropImageRect(pinnedSize: CGSize, in bounds: CGRect) -> CGRect {
    CGRect(
        x: bounds.midX - pinnedSize.width / 2,
        y: bounds.midY - pinnedSize.height / 2,
        width: pinnedSize.width,
        height: pinnedSize.height
    )
}

/// Converts a point in the overlay view's own coordinate space to a
/// normalized (0...1) point within `imageRect`, clamping to that range. A
/// point from the margin band (outside `imageRect` entirely) naturally
/// clamps to exactly 0 or 1 — the "overshoot to reach the true edge"
/// behavior the crop tool relies on.
func normalizedPoint(from viewPoint: CGPoint, in imageRect: CGRect) -> CGPoint {
    guard imageRect.width > 0, imageRect.height > 0 else { return .zero }
    let x = (viewPoint.x - imageRect.minX) / imageRect.width
    let y = (viewPoint.y - imageRect.minY) / imageRect.height
    return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
}

/// Converts a normalized rect back into the overlay view's own coordinate
/// space, given where the image itself sits within it.
func viewRect(for rect: NormalizedRect, in imageRect: CGRect) -> CGRect {
    CGRect(
        x: imageRect.minX + rect.x * imageRect.width,
        y: imageRect.minY + rect.y * imageRect.height,
        width: rect.width * imageRect.width,
        height: rect.height * imageRect.height
    )
}

import CoreGraphics

/// Aspect ratio constraint for the crop tool. Declaration order is also the
/// cycling order for the Alt+-/+ shortcut and the dropdown's listed order.
enum CropAspectRatio: CaseIterable {
    case original
    case free
    case r9x16
    case r10x16
    case r2x3
    case r3x4
    case r4x5
    case r1x1
    case r5x4
    case r4x3
    case r3x2
    case r16x10
    case r16x9

    var label: String {
        switch self {
        case .original: return "Original"
        case .free: return "Free"
        case .r9x16: return "9:16"
        case .r10x16: return "10:16"
        case .r2x3: return "2:3"
        case .r3x4: return "3:4"
        case .r4x5: return "4:5"
        case .r1x1: return "1:1"
        case .r5x4: return "5:4"
        case .r4x3: return "4:3"
        case .r3x2: return "3:2"
        case .r16x10: return "16:10"
        case .r16x9: return "16:9"
        }
    }

    /// width/height for this ratio. `.original` resolves against the image's
    /// own aspect; `.free` returns nil (unconstrained).
    func widthToHeight(imageAspect: CGFloat) -> CGFloat? {
        switch self {
        case .original: return imageAspect
        case .free: return nil
        case .r9x16: return 9.0 / 16.0
        case .r10x16: return 10.0 / 16.0
        case .r2x3: return 2.0 / 3.0
        case .r3x4: return 3.0 / 4.0
        case .r4x5: return 4.0 / 5.0
        case .r1x1: return 1.0
        case .r5x4: return 5.0 / 4.0
        case .r4x3: return 4.0 / 3.0
        case .r3x2: return 3.0 / 2.0
        case .r16x10: return 16.0 / 10.0
        case .r16x9: return 16.0 / 9.0
        }
    }

    /// Alt+1...Alt+9 shortcuts, in order (Alt+0 is `.free`, handled
    /// separately since it isn't part of this list).
    static let digitShortcuts: [CropAspectRatio] = allCases.filter { $0 != .free }.prefix(9).map { $0 }

    /// Cycles forward/backward through `allCases`, wrapping around.
    func cycled(forward: Bool) -> CropAspectRatio {
        let cases = CropAspectRatio.allCases
        guard let index = cases.firstIndex(of: self) else { return self }
        let count = cases.count
        let nextIndex = forward
            ? (index + 1) % count
            : (index - 1 + count) % count
        return cases[nextIndex]
    }
}

/// Tuning constants for the crop tool.
enum CropMetrics {
    /// Gap kept between the image and the screen edge while cropping, on
    /// all four sides. The crop window covers the whole screen, so this
    /// space is always available to start a drag from outside the image
    /// and still land exactly on its edge.
    static let screenPadding: CGFloat = 64
}

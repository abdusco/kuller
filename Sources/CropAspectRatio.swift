import CoreGraphics
import Foundation

/// Aspect ratio constraint for the crop tool. Declaration order is also the
/// cycling order for the Alt+-/+ shortcut and the dropdown's listed order.
struct CropAspectRatio: Hashable, Codable, CaseIterable {
    let label: String
    let ratio: Double?

    static let original = CropAspectRatio(label: "Original", ratio: nil)
    static let free = CropAspectRatio(label: "Free", ratio: nil)
    static let r9x16 = custom(width: 9, height: 16)
    static let r10x16 = custom(width: 10, height: 16)
    static let r2x3 = custom(width: 2, height: 3)
    static let r3x4 = custom(width: 3, height: 4)
    static let r4x5 = custom(width: 4, height: 5)
    static let r1x1 = custom(width: 1, height: 1)
    static let r5x4 = custom(width: 5, height: 4)
    static let r4x3 = custom(width: 4, height: 3)
    static let r3x2 = custom(width: 3, height: 2)
    static let r16x10 = custom(width: 16, height: 10)
    static let r16x9 = custom(width: 16, height: 9)
    static let allCases: [CropAspectRatio] = [original, free, r9x16, r10x16, r2x3, r3x4,
                                             r4x5, r1x1, r5x4, r4x3, r3x2, r16x10, r16x9]

    static func custom(width: Double, height: Double) -> CropAspectRatio {
        CropAspectRatio(label: "\(width.formatted(.number.grouping(.never))):\(height.formatted(.number.grouping(.never)))",
                        ratio: width / height)
    }

    /// width/height for this ratio. `.original` resolves against the image's
    /// own aspect; `.free` returns nil (unconstrained).
    func widthToHeight(imageAspect: CGFloat) -> CGFloat? {
        self == .original ? imageAspect : ratio.map { CGFloat($0) }
    }

    /// Alt+1...Alt+9 shortcuts, in order (Alt+0 is `.free`, handled
    /// separately since it isn't part of this list).
    static let digitShortcuts: [CropAspectRatio] = allCases.filter { $0 != .free }.prefix(9).map { $0 }

    /// Cycles forward/backward through `allCases`, wrapping around.
    func cycled(forward: Bool, cases: [CropAspectRatio] = allCases) -> CropAspectRatio {
        guard let index = cases.firstIndex(of: self) else { return cases.first ?? .original }
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

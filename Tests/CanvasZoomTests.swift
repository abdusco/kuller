import CoreGraphics

@main
enum CanvasZoomTests {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let centered = CGRect(x: 300, y: 200, width: 600, height: 400)
        let frameCases: [(String, CGSize, CGRect, CGRect, CGRect)] = [
            ("grow around center", CGSize(width: 900, height: 600), centered, screen,
             CGRect(x: 150, y: 100, width: 900, height: 600)),
            ("height reaches edge first", CGSize(width: 700, height: 1400), centered, screen,
             CGRect(x: 250, y: 0, width: 700, height: 800)),
            ("width reaches edge first", CGSize(width: 1800, height: 600), centered, screen,
             CGRect(x: 0, y: 100, width: 1200, height: 600)),
            ("both axes reach edges", CGSize(width: 2400, height: 1600), centered, screen, screen),
            ("zoom out restores image shape", CGSize(width: 600, height: 400), screen, screen, centered),
            ("shift inward near screen edge", CGSize(width: 900, height: 600),
             CGRect(x: 0, y: 0, width: 600, height: 400), screen,
             CGRect(x: 0, y: 0, width: 900, height: 600)),
            ("display with negative origin", CGSize(width: 2400, height: 1600),
             CGRect(x: -900, y: 300, width: 600, height: 400),
             CGRect(x: -1200, y: 100, width: 1200, height: 800),
             CGRect(x: -1200, y: 100, width: 1200, height: 800)),
        ]
        for (name, imageSize, frame, bounds, expected) in frameCases {
            let actual = zoomedCanvasFrame(imageSize: imageSize, around: frame, within: bounds)
            precondition(actual == expected, "\(name): \(actual) != \(expected)")
        }

        let offsetCases: [(String, CGSize, CGSize, CGSize, CGSize)] = [
            ("pan within image", CGSize(width: 100, height: -100),
             CGSize(width: 1800, height: 1200), screen.size, CGSize(width: 100, height: -100)),
            ("stop at image edges", CGSize(width: 900, height: -900),
             CGSize(width: 1800, height: 1200), screen.size, CGSize(width: 300, height: -200)),
            ("fitted image resets pan", CGSize(width: 100, height: -100),
             centered.size, centered.size, .zero),
            ("only overflowing axis pans", CGSize(width: -900, height: 900),
             CGSize(width: 1800, height: 600), CGSize(width: 1200, height: 600),
             CGSize(width: -300, height: 0)),
        ]
        for (name, offset, imageSize, viewport, expected) in offsetCases {
            let actual = clampedImageOffset(offset, imageSize: imageSize, viewport: viewport)
            precondition(actual == expected, "\(name): \(actual) != \(expected)")
        }
        print("Passed \(frameCases.count + offsetCases.count) canvas zoom cases")
    }
}

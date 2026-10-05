import AppKit
import SwiftUI
import ImageIO

private var resizedSizes: [CGSize] = []

// Record window sizing independently of main.swift's application startup.
func resizeCanvasWindow(toImageSize size: CGSize) {
    resizedSizes.append(size)
}

@main
enum ImageViewerTests {
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuller-viewer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 320,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let cases: [(String, Int, NormalizedRect?, CGSize)] = [
            ("upright", 1, nil, CGSize(width: 640, height: 320)),
            ("rotated", 6, nil, CGSize(width: 320, height: 640)),
            ("cropped", 1, NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
             CGSize(width: 320, height: 320)),
            ("rotated crop", 8, NormalizedRect(x: 0, y: 0, width: 1, height: 0.5),
             CGSize(width: 320, height: 320)),
        ]
        for (name, orientation, crop, expected) in cases {
            let url = directory.appendingPathComponent("\(name).jpg")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, bitmap.cgImage!,
                                       [kCGImagePropertyOrientation: orientation] as CFDictionary)
            precondition(CGImageDestinationFinalize(destination))
            let sourceSize = (5...8).contains(orientation)
                ? CGSize(width: 320, height: 640) : CGSize(width: 640, height: 320)
            let thumbnailSize = CGSize(width: sourceSize.width / 2, height: sourceSize.height / 2)
            let started = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let cache = ThumbnailCache { _, pixels in
                if pixels > 320 {
                    started.signal()
                    precondition(release.wait(timeout: .now() + 5) == .success)
                    return NSImage(cgImage: bitmap.cgImage!, size: sourceSize)
                }
                return NSImage(cgImage: bitmap.cgImage!, size: thumbnailSize)
            }
            var thumbnailReady = false
            cache.thumbnail(for: url) { image in
                precondition(image != nil)
                thumbnailReady = true
            }
            wait { thumbnailReady }
            resizedSizes = []
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: ImageViewerView(item: ImageItem(url: url), cropRect: crop,
                                                                 imageCache: cache))
            hosting.sizingOptions = []
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            wait { !resizedSizes.isEmpty }
            precondition(resizedSizes == [expected], "\(name): initial sizing used thumbnail dimensions")
            // The full preview is held in its decoder: this sizing assertion
            // must pass while the only available image is the thumbnail.
            precondition(started.wait(timeout: .now() + 5) == .success)
            var previewReady = false
            cache.fullImage(for: url) { image in
                precondition(image != nil)
                previewReady = true
            }
            release.signal()
            wait { previewReady }
            hosting.layoutSubtreeIfNeeded()
            precondition(resizedSizes == [expected], "\(name): preview upgrade resized the window")
            window.contentView = nil
            window.close()
        }
        print("Passed \(cases.count) viewer sizing cases")
    }

    private static func wait(until completed: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !completed(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(completed(), "Timed out waiting for viewer")
    }
}

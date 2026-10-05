import AppKit
import Foundation

@main
enum ThumbnailCacheTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuller-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let data = bitmap.representation(using: .png, properties: [:])!
        let imageURL = directory.appendingPathComponent("image.png")
        try data.write(to: imageURL)
        let missingURL = directory.appendingPathComponent("missing.png")

        let cases: [(String, URL, Bool)] = [
            ("cold image", imageURL, true),
            ("cached image", imageURL, true),
            ("missing image", missingURL, false),
        ]
        for (name, url, exists) in cases {
            var returned = false
            var completed = false
            ThumbnailCache.shared.thumbnail(for: url) { image in
                precondition(returned, "\(name): thumbnail callback ran inline")
                precondition(Thread.isMainThread, "\(name): thumbnail callback ran off main")
                precondition((image != nil) == exists, "\(name): unexpected thumbnail")
                if let image { precondition(image.size == CGSize(width: 32, height: 16)) }
                completed = true
            }
            returned = true
            wait { completed }

            returned = false
            completed = false
            ThumbnailCache.shared.fullImage(for: url) { image in
                precondition(returned, "\(name): full image callback ran inline")
                precondition(Thread.isMainThread, "\(name): full image callback ran off main")
                precondition((image != nil) == exists, "\(name): unexpected full image")
                if let image { precondition(image.size == CGSize(width: 32, height: 16)) }
                completed = true
            }
            returned = true
            wait { completed }

            returned = false
            completed = false
            ThumbnailCache.shared.aspectRatio(for: url) { ratio in
                precondition(returned, "\(name): aspect callback ran inline")
                precondition(Thread.isMainThread, "\(name): aspect callback ran off main")
                precondition(abs(ratio - (exists ? 2 : 4.0 / 3.0)) < 0.0001)
                completed = true
            }
            returned = true
            wait { completed }
        }

        let largeBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 320,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let largeURL = directory.appendingPathComponent("large.png")
        try largeBitmap.representation(using: .png, properties: [:])!.write(to: largeURL)
        let sizes: [(String, Bool, CGFloat, CGSize)] = [
            ("shared thumbnail", true, 320, CGSize(width: 320, height: 160)),
            ("small preview", false, 160, CGSize(width: 160, height: 80)),
            ("larger preview", false, 480, CGSize(width: 480, height: 240)),
            ("cached small preview", false, 160, CGSize(width: 160, height: 80)),
        ]
        for (name, thumbnail, pixels, expected) in sizes {
            var completed = false
            let completion: (NSImage?) -> Void = { image in
                precondition(image?.size == expected, "\(name): incorrect decoded size")
                if thumbnail {
                    precondition(ThumbnailCache.shared.cachedThumbnail(for: largeURL) === image)
                }
                completed = true
            }
            if thumbnail {
                ThumbnailCache.shared.thumbnail(for: largeURL, completion: completion)
            } else {
                ThumbnailCache.shared.fullImage(for: largeURL, maxPixelSize: pixels, completion: completion)
            }
            wait { completed }
        }

        // Hold the first decode open so subsequent requests must join it.
        // Include failed decodes: every waiting caller still needs an answer.
        let sharingCases: [(String, Bool, Bool)] = [
            ("thumbnail", true, true),
            ("preview", false, true),
            ("failed thumbnail", true, false),
            ("failed preview", false, false),
        ]
        for (name, thumbnail, succeeds) in sharingCases {
            let started = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var decodes = 0
            let cache = ThumbnailCache { _, _ in
                lock.lock()
                decodes += 1
                lock.unlock()
                started.signal()
                precondition(release.wait(timeout: .now() + 5) == .success)
                return succeeds ? NSImage(cgImage: bitmap.cgImage!, size: CGSize(width: 32, height: 16)) : nil
            }
            var callbacks = 0
            let completion: (NSImage?) -> Void = { image in
                precondition(Thread.isMainThread, "\(name): callback ran off main")
                precondition((image != nil) == succeeds)
                callbacks += 1
            }
            if thumbnail {
                cache.thumbnail(for: imageURL, completion: completion)
            } else {
                cache.fullImage(for: imageURL, qos: .utility, completion: completion)
            }
            precondition(started.wait(timeout: .now() + 5) == .success)
            for _ in 0..<4 {
                if thumbnail {
                    cache.thumbnail(for: imageURL, completion: completion)
                } else {
                    cache.fullImage(for: imageURL, completion: completion)
                }
            }
            release.signal()
            wait { callbacks == 5 }
            lock.lock()
            precondition(decodes == 1, "\(name): duplicate requests decoded \(decodes) times")
            lock.unlock()
        }
        print("Passed \(cases.count * 3 + sizes.count + sharingCases.count) thumbnail cache cases")
    }

    private static func wait(until completed: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !completed(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(completed(), "Timed out waiting for image load")
    }
}

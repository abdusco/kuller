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
        print("Passed \(cases.count * 3) thumbnail cache cases")
    }

    private static func wait(until completed: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !completed(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(completed(), "Timed out waiting for image load")
    }
}

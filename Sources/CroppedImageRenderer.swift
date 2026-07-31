import Foundation
import ImageIO

/// Renders a committed crop to a real file on disk, lazily — only when
/// something outside the app actually needs bytes (Quick Look, the
/// pasteboard, drag-to-Finder, export). Thumbnails and the culling preview
/// stay entirely in-memory (`NSImage.cropped(to:)` in NormalizedRect.swift)
/// and never touch this.
enum CroppedImageRenderer {
    private static let queue = DispatchQueue(label: "kuller.crop-render")
    private static var cache: [UUID: (rect: NormalizedRect, url: URL)] = [:]

    private static let tempDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kuller-crops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Resolves the URL that should actually be handed to Quick Look / the
    /// pasteboard / an export copy: `item.url` itself if there's no real
    /// crop, otherwise a rendered temp file (rendering + caching it first if
    /// this exact rect hasn't been rendered yet).
    static func resolvedURL(for item: ImageItem, cropRects: [UUID: NormalizedRect], completion: @escaping (URL) -> Void) {
        guard let rect = cropRects[item.id], rect != .fullImage else {
            completion(item.url)
            return
        }
        queue.async {
            let url = resolveOnQueue(item: item, rect: rect)
            DispatchQueue.main.async { completion(url) }
        }
    }

    /// Same resolution, blocking — for drag-to-Finder, the one call site
    /// that's inherently synchronous (`NSPasteboardWriting` is queried by
    /// AppKit synchronously at drag time). A cache hit returns instantly; a
    /// miss blocks the caller for one decode+crop+encode.
    static func resolvedURLSync(for item: ImageItem, cropRects: [UUID: NormalizedRect]) -> URL {
        guard let rect = cropRects[item.id], rect != .fullImage else { return item.url }
        return queue.sync { resolveOnQueue(item: item, rect: rect) }
    }

    /// Deletes any cached render + its temp file for a deleted virtual copy.
    static func invalidate(itemID: UUID) {
        queue.async {
            if cache.removeValue(forKey: itemID) != nil {
                try? FileManager.default.removeItem(at: tempDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true))
            }
        }
    }

    private static func resolveOnQueue(item: ImageItem, rect: NormalizedRect) -> URL {
        if let cached = cache[item.id], cached.rect == rect, FileManager.default.fileExists(atPath: cached.url.path) {
            return cached.url
        }
        // Re-rendering (e.g. after the same virtual copy was re-cropped)
        // overwrites the same path below, since it's keyed by item id, not
        // by rect — nothing extra to clean up here first.
        guard let rendered = render(item: item, rect: rect) else { return item.url }
        cache[item.id] = (rect, rendered)
        return rendered
    }

    private static func render(item: ImageItem, rect: NormalizedRect) -> URL? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, sourceOptions as CFDictionary),
              let type = CGImageSourceGetType(source) else { return nil }

        // Full-resolution, orientation-corrected decode — the same
        // technique ThumbnailCache.downsample uses for previews, so these
        // pixels line up with what the user actually cropped against.
        let pixelSize = ThumbnailCache.quickPixelSize(of: item.url)
        let maxPixelSize = max(pixelSize?.width ?? 0, pixelSize?.height ?? 0)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
        ]
        guard let fullImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        let pixelWidth = CGFloat(fullImage.width)
        let pixelHeight = CGFloat(fullImage.height)
        let cropRect = CGRect(
            x: rect.x * pixelWidth,
            y: (1 - rect.y - rect.height) * pixelHeight,
            width: rect.width * pixelWidth,
            height: rect.height * pixelHeight
        ).integral
        guard let cropped = fullImage.cropping(to: cropRect) else { return nil }

        // A subdirectory per item id keeps filenames unique across items
        // while the leaf name itself stays human-readable (item.displayName,
        // e.g. "img1_crop1.jpg") — that's what Quick Look, the Finder
        // pasteboard, and drag-and-drop all actually display to the user,
        // so it can't be the bare UUID.
        let destinationDir = tempDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let destination = destinationDir.appendingPathComponent(item.displayName)
        try? FileManager.default.removeItem(at: destination)
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, type, 1, nil) else { return nil }

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        // The transform-decode above already rotated the pixels upright, so
        // keeping the source's original orientation tag would make viewers
        // double-rotate the result.
        properties[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(dest, cropped, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return destination
    }
}

import AppKit
import ImageIO
import Foundation

/// Async, cached loader for downsampled thumbnails and full-size images.
/// Uses CGImageSource downsampling so large photos don't get fully decoded
/// just to render a small strip thumbnail.
/// Completions always run asynchronously on the main queue, including cache
/// hits: callers may update SwiftUI state and resize its hosting window.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private let fullImageCache = NSCache<NSURL, NSImage>()
    private let queue = DispatchQueue(label: "kuller.thumbnail-cache", attributes: .concurrent)
    private var aspectRatios: [URL: CGFloat] = [:]
    private let aspectLock = NSLock()

    private init() {
        thumbnailCache.countLimit = 2000
        fullImageCache.countLimit = 4
    }

    func thumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        if let cached = thumbnailCache.object(forKey: url as NSURL) {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        queue.async {
            let image = Self.downsample(url: url, maxPixelSize: 320)
            if let image = image {
                self.thumbnailCache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func cachedThumbnail(for url: URL) -> NSImage? {
        thumbnailCache.object(forKey: url as NSURL)
    }

    func fullImage(for url: URL, maxPixelSize: CGFloat = 4096, qos: DispatchQoS = .userInitiated, completion: @escaping (NSImage?) -> Void) {
        if let cached = fullImageCache.object(forKey: url as NSURL) {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        queue.async(qos: qos) {
            let image = Self.downsample(url: url, maxPixelSize: maxPixelSize)
            if let image = image {
                self.fullImageCache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// Warm the two following images and one preceding image. Virtual
    /// copies share their source URL, so each source is requested only once.
    func prefetch(items: [ImageItem], currentIndex: Int) {
        guard items.indices.contains(currentIndex) else { return }
        var urls: Set<URL> = [items[currentIndex].url]
        for index in [currentIndex + 1, currentIndex + 2, currentIndex - 1] {
            guard items.indices.contains(index), urls.insert(items[index].url).inserted else { continue }
            fullImage(for: items[index].url, qos: .utility) { _ in }
        }
    }

    /// Width / height of an image, from metadata only. Cached and answered
    /// asynchronously on repeat calls so the thumbnail strip can lay out
    /// variable-height rows without re-reading files while scrolling.
    func aspectRatio(for url: URL, completion: @escaping (CGFloat) -> Void) {
        if let cached = cachedAspectRatio(for: url) {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        queue.async {
            let size = Self.quickPixelSize(of: url)
            let ratio: CGFloat
            if let size = size, size.width > 0, size.height > 0 {
                ratio = size.width / size.height
            } else {
                ratio = 4.0 / 3.0
            }
            self.aspectLock.lock()
            self.aspectRatios[url] = ratio
            self.aspectLock.unlock()
            DispatchQueue.main.async {
                completion(ratio)
            }
        }
    }

    func cachedAspectRatio(for url: URL) -> CGFloat? {
        aspectLock.lock()
        defer { aspectLock.unlock() }
        return aspectRatios[url]
    }

    /// Reads just the pixel dimensions from an image's metadata, without
    /// decoding it — fast enough to call synchronously (e.g. to size a
    /// window before the full image has loaded).
    static func quickPixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func downsample(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Finish decoding on this worker rather than deferring it until
            // AppKit draws the image on the main thread.
            kCGImageSourceShouldCacheImmediately: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }
}

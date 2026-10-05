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

    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let fullImageCache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "kuller.thumbnail-cache", attributes: .concurrent)
    private let decodeQueue = OperationQueue()
    private final class PendingImage {
        let id = UUID()
        let url: URL
        let operation = BlockOperation()
        var completions: [(NSImage?) -> Void]

        init(url: URL, completion: @escaping (NSImage?) -> Void) {
            self.url = url
            self.completions = [completion]
        }
    }
    private var pendingImages: [String: PendingImage] = [:]
    private let imageLock = NSLock()
    private let decoder: (URL, CGFloat) -> NSImage?
    private var aspectRatios: [URL: CGFloat] = [:]
    private let aspectLock = NSLock()

    init(decoder: ((URL, CGFloat) -> NSImage?)? = nil) {
        self.decoder = decoder ?? Self.downsample
        decodeQueue.name = "kuller.image-decode"
        decodeQueue.maxConcurrentOperationCount = 2
        thumbnailCache.countLimit = 2000
        fullImageCache.countLimit = 4
    }

    func thumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        loadImage(for: url, maxPixelSize: 320, key: "thumbnail:\(url.absoluteString)",
                  cache: thumbnailCache, qos: .userInitiated, completion: completion)
    }

    func cachedThumbnail(for url: URL) -> NSImage? {
        thumbnailCache.object(forKey: "thumbnail:\(url.absoluteString)" as NSString)
    }

    func fullImage(for url: URL, maxPixelSize: CGFloat = 4096, qos: DispatchQoS = .userInitiated, completion: @escaping (NSImage?) -> Void) {
        loadImage(for: url, maxPixelSize: maxPixelSize, key: "preview:\(maxPixelSize):\(url.absoluteString)",
                  cache: fullImageCache, qos: qos, completion: completion)
    }

    private func loadImage(for url: URL, maxPixelSize: CGFloat, key: String,
                           cache: NSCache<NSString, NSImage>, qos: DispatchQoS,
                           completion: @escaping (NSImage?) -> Void) {
        // Cache lookup and registration share a lock so a decode finishing
        // between them cannot cause a second decode of the same request.
        imageLock.lock()
        if let cached = cache.object(forKey: key as NSString) {
            imageLock.unlock()
            DispatchQueue.main.async { completion(cached) }
            return
        }
        if let pending = pendingImages[key] {
            pending.completions.append(completion)
            if qos.qosClass == .userInitiated, !pending.operation.isExecuting {
                pending.operation.qualityOfService = .userInitiated
                pending.operation.queuePriority = .high
            }
            imageLock.unlock()
            return
        }
        let pending = PendingImage(url: url, completion: completion)
        let requestID = pending.id
        pending.operation.qualityOfService = qos.qosClass == .utility ? .utility : .userInitiated
        pending.operation.queuePriority = qos.qosClass == .utility ? .low : .high
        pending.operation.addExecutionBlock {
            let image = self.decoder(url, maxPixelSize)
            self.imageLock.lock()
            // A cancelled prefetch may already have entered its decoder.
            // It must not complete a newer request for the same source.
            guard self.pendingImages[key]?.id == requestID else {
                self.imageLock.unlock()
                return
            }
            if let image = image {
                cache.setObject(image, forKey: key as NSString)
            }
            let completions = self.pendingImages.removeValue(forKey: key)?.completions ?? []
            self.imageLock.unlock()
            DispatchQueue.main.async {
                for completion in completions { completion(image) }
            }
        }
        pendingImages[key] = pending
        imageLock.unlock()
        decodeQueue.addOperation(pending.operation)
    }

    /// Warm the two following images and one preceding image. Virtual
    /// copies share their source URL, so each source is requested only once.
    func prefetch(items: [ImageItem], currentIndex: Int) {
        var urls = Set<URL>()
        var neighbors: [URL] = []
        if items.indices.contains(currentIndex) { urls.insert(items[currentIndex].url) }
        for index in [currentIndex + 1, currentIndex + 2, currentIndex - 1] {
            guard items.indices.contains(currentIndex), items.indices.contains(index),
                  urls.insert(items[index].url).inserted else { continue }
            neighbors.append(items[index].url)
        }
        imageLock.lock()
        let obsolete = pendingImages.filter { _, pending in
            pending.operation.qualityOfService == .utility && !pending.operation.isExecuting
                && !urls.contains(pending.url)
        }.map(\.key)
        for key in obsolete {
            pendingImages.removeValue(forKey: key)?.operation.cancel()
        }
        imageLock.unlock()
        for url in neighbors { fullImage(for: url, qos: .utility) { _ in } }
    }

    func cancelPrefetching() {
        prefetch(items: [], currentIndex: 0)
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

import AppKit
import ImageIO
import Foundation

/// Async, cached loader for downsampled thumbnails and full-size images.
/// Uses CGImageSource downsampling so large photos don't get fully decoded
/// just to render a small strip thumbnail.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private let fullImageCache = NSCache<NSURL, NSImage>()
    private let queue = DispatchQueue(label: "kuller.thumbnail-cache", attributes: .concurrent)

    private init() {
        thumbnailCache.countLimit = 2000
        fullImageCache.countLimit = 4
    }

    func thumbnail(for url: URL, maxPixelSize: CGFloat = 240, completion: @escaping (NSImage?) -> Void) {
        if let cached = thumbnailCache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        queue.async {
            let image = Self.downsample(url: url, maxPixelSize: maxPixelSize)
            if let image = image {
                self.thumbnailCache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func fullImage(for url: URL, maxPixelSize: CGFloat = 4096, completion: @escaping (NSImage?) -> Void) {
        if let cached = fullImageCache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        queue.async {
            let image = Self.downsample(url: url, maxPixelSize: maxPixelSize)
            if let image = image {
                self.fullImageCache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
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
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }
}

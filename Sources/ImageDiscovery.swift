import Foundation

enum ImageDiscovery {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp", "webp",
    ]

    static func isSupportedImageFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Resolves a list of CLI path arguments into a flat, ordered list of image files.
    /// Files are included directly (if a supported image); directories are walked
    /// recursively and their matching contents are sorted alphabetically (case-insensitive).
    /// Throws a descriptive error for missing paths or unsupported files.
    static func resolveImages(fromArguments paths: [String]) throws -> [ImageItem] {
        let fm = FileManager.default
        var result: [ImageItem] = []

        for rawPath in paths {
            let expandedPath = (rawPath as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false

            guard fm.fileExists(atPath: expandedPath, isDirectory: &isDirectory) else {
                throw CLIError.message("path not found: \(rawPath)")
            }

            let url = URL(fileURLWithPath: expandedPath)

            if isDirectory.boolValue {
                let images = try walkDirectory(url, fileManager: fm)
                result.append(contentsOf: images)
            } else {
                guard isSupportedImageFile(url) else {
                    throw CLIError.message("unsupported file type: \(rawPath)")
                }
                result.append(ImageItem(url: url))
            }
        }

        return result
    }

    private static func walkDirectory(_ directory: URL, fileManager fm: FileManager) throws -> [ImageItem] {
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            throw CLIError.message("could not read directory: \(directory.path)")
        }

        var files: [URL] = []
        for entry in enumerator {
            guard let fileURL = entry as? URL else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if isSupportedImageFile(fileURL) {
                files.append(fileURL)
            }
        }

        files.sort { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        return files.map { ImageItem(url: $0) }
    }
}

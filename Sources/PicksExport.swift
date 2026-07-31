import Foundation

enum PicksExport {
    /// Copies the given items into `directory` (creating it, including any
    /// missing intermediate directories, if it doesn't exist yet). Filename
    /// collisions get a numeric suffix rather than overwriting.
    static func copyPicks(_ items: [ImageItem], cropRects: [UUID: NormalizedRect], to directory: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("error: could not create \(directory.path): \(error)\n".utf8))
            return
        }

        var copiedCount = 0
        for item in items {
            // The destination filename is derived from the item's own
            // display name (so a virtual copy exports as e.g.
            // "img1_crop1.jpg", not a collision-suffixed "img1-1.jpg"), but
            // the bytes copied come from its committed crop, if any.
            let destination = uniqueDestination(filename: item.displayName, in: directory, fileManager: fm)
            let source = CroppedImageRenderer.resolvedURLSync(for: item, cropRects: cropRects)
            do {
                try fm.copyItem(at: source, to: destination)
                copiedCount += 1
            } catch {
                FileHandle.standardError.write(Data("warning: failed to copy \(item.url.lastPathComponent): \(error)\n".utf8))
            }
        }
        print("Copied \(copiedCount) pick\(copiedCount == 1 ? "" : "s") to \(directory.path)")
    }

    private static func uniqueDestination(filename: String, in directory: URL, fileManager fm: FileManager) -> URL {
        var candidate = directory.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let baseName = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var suffix = 1
        repeat {
            let name = ext.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(ext)"
            candidate = directory.appendingPathComponent(name)
            suffix += 1
        } while fm.fileExists(atPath: candidate.path)

        return candidate
    }
}

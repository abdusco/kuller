import Foundation

enum PicksExport {
    /// Copies the given items into `directory` (creating it, including any
    /// missing intermediate directories, if it doesn't exist yet). Filename
    /// collisions get a numeric suffix rather than overwriting.
    static func copyPicks(_ items: [ImageItem], to directory: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("error: could not create \(directory.path): \(error)\n".utf8))
            return
        }

        var copiedCount = 0
        for item in items {
            let destination = uniqueDestination(for: item.url, in: directory, fileManager: fm)
            do {
                try fm.copyItem(at: item.url, to: destination)
                copiedCount += 1
            } catch {
                FileHandle.standardError.write(Data("warning: failed to copy \(item.url.lastPathComponent): \(error)\n".utf8))
            }
        }
        print("Copied \(copiedCount) pick\(copiedCount == 1 ? "" : "s") to \(directory.path)")
    }

    private static func uniqueDestination(for source: URL, in directory: URL, fileManager fm: FileManager) -> URL {
        var candidate = directory.appendingPathComponent(source.lastPathComponent)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let baseName = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var suffix = 1
        repeat {
            let name = ext.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(ext)"
            candidate = directory.appendingPathComponent(name)
            suffix += 1
        } while fm.fileExists(atPath: candidate.path)

        return candidate
    }
}

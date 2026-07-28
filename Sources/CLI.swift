import Foundation

enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

struct CLIResult {
    let images: [ImageItem]
    /// If set, once culling finishes the app copies picks straight to this
    /// directory and quits, skipping the review screen entirely.
    let copyPicksTo: URL?
}

enum CLI {
    static let version = "0.1.0"

    static let usage = """
    Usage: kuller [--help] [--version] [--copy-picks-to <dir>] <path> [path ...]

    Cull and pick images from one or more files or folders.
    Folders are scanned recursively for image files
    (jpg, jpeg, png, tiff, tif, gif, bmp, webp).

    Options:
      -h, --help              Show this help message and exit
      --version               Show version information and exit
      --copy-picks-to <dir>   When culling finishes, copy picks straight to
                               <dir> (created if needed) and quit, instead of
                               showing the review screen.

    Keyboard shortcuts (in app):
      p          Pick the current image and advance
      x          Reject the current image and advance
      j / k      Next / previous image, without deciding
      <- / ->    Same as j / k
      Cmd+Return Submit now (undecided images become rejects)
      Esc/Cmd+W  Exit (confirms if images are still undecided)
      Cmd+Q      Quit immediately

    Review screen:
      p / x      Move the selected images to Picks / Rejects
      Space      Preview the selected images with Quick Look
      Cmd+A      Select all in the focused column
      Cmd+C      Copy the selected images as files
    """

    /// Parses CommandLine.arguments (excluding the executable name) and either
    /// handles --help/--version directly (returning nil to signal "exit now"),
    /// or returns the resolved list of images to cull plus any options.
    static func run(arguments: [String]) -> CLIResult? {
        if arguments.isEmpty {
            FileHandle.standardError.write(Data((usage + "\n\nerror: no paths given\n").utf8))
            exit(1)
        }

        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            exit(0)
        }

        if arguments.contains("--version") {
            print("kuller \(version)")
            exit(0)
        }

        var remaining = arguments
        var copyPicksTo: URL?

        if let flagIndex = remaining.firstIndex(of: "--copy-picks-to") {
            let valueIndex = flagIndex + 1
            guard remaining.indices.contains(valueIndex) else {
                FileHandle.standardError.write(Data("error: --copy-picks-to requires a directory path\n".utf8))
                exit(1)
            }
            let path = remaining[valueIndex]
            copyPicksTo = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            remaining.remove(at: valueIndex)
            remaining.remove(at: flagIndex)
        }

        if remaining.isEmpty {
            FileHandle.standardError.write(Data((usage + "\n\nerror: no paths given\n").utf8))
            exit(1)
        }

        do {
            let images = try ImageDiscovery.resolveImages(fromArguments: remaining)
            if images.isEmpty {
                FileHandle.standardError.write(Data("error: no images found\n".utf8))
                exit(1)
            }
            return CLIResult(images: images, copyPicksTo: copyPicksTo)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}

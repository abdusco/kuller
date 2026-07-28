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

enum CLI {
    static let version = "0.1.0"

    static let usage = """
    Usage: kuller [--help] [--version] <path> [path ...]

    Cull and pick images from one or more files or folders.
    Folders are scanned recursively for image files
    (jpg, jpeg, png, tiff, tif, gif, bmp, webp).

    Options:
      -h, --help       Show this help message and exit
      --version        Show version information and exit

    Keyboard shortcuts (in app):
      p          Pick the current image and advance
      x          Reject the current image and advance
      <- / ->    Browse without deciding
      Cmd+Return Submit now (undecided images become rejects)
    """

    /// Parses CommandLine.arguments (excluding the executable name) and either
    /// handles --help/--version directly (returning nil to signal "exit now"),
    /// or returns the resolved list of images to cull.
    static func run(arguments: [String]) -> [ImageItem]? {
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

        do {
            let images = try ImageDiscovery.resolveImages(fromArguments: arguments)
            if images.isEmpty {
                FileHandle.standardError.write(Data("error: no images found\n".utf8))
                exit(1)
            }
            return images
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}

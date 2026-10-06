import Foundation

struct ImageItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    /// True for a crop-tool-generated duplicate of another item (same
    /// `url`, distinct `id`) — see `AppState.insertVirtualCopy`. Otherwise
    /// this is one of the originally-discovered files.
    let isVirtualCopy: Bool
    /// 1-based index among virtual copies made from the same original,
    /// fixed at creation time (not renumbered if an earlier copy is later
    /// deleted). Meaningless when `isVirtualCopy` is false.
    let copyIndex: Int

    init(url: URL, isVirtualCopy: Bool = false, copyIndex: Int = 0) {
        self.id = UUID()
        self.url = url
        self.isVirtualCopy = isVirtualCopy
        self.copyIndex = copyIndex
    }

    /// `$original_crop#n.$ext` for a virtual copy (e.g. "img1_crop1.jpg"),
    /// used for on-screen labels and as the filename of rendered crops.
    var displayName: String {
        guard isVirtualCopy else { return url.lastPathComponent }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let name = "\(base)_crop\(copyIndex)"
        return ext.isEmpty ? name : "\(name).\(ext)"
    }
}

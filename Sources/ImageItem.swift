import Foundation

struct ImageItem: Identifiable, Hashable {
    let id: UUID
    let url: URL

    init(url: URL) {
        self.id = UUID()
        self.url = url
    }

    var displayName: String {
        url.lastPathComponent
    }
}

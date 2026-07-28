import AppKit
import SwiftUI

/// Which review column a grid represents. Also identifies the decision an
/// item is reclassified to when dropped onto that column.
enum ReviewColumnKind {
    case picks
    case rejects

    var decision: Decision {
        switch self {
        case .picks: return .pick
        case .rejects: return .reject
        }
    }
}

/// Drag payload for a single grid item: carries both a real file-URL
/// representation (so dropping onto Finder or another app copies the file)
/// and a private identifier representation (so dropping onto our own other
/// grid can look the item back up and reclassify it, without accepting
/// arbitrary external file drops).
final class DraggableImageReference: NSObject, NSPasteboardWriting {
    static let itemIDType = NSPasteboard.PasteboardType("com.kuller.image-item-id")

    let item: ImageItem

    init(item: ImageItem) {
        self.item = item
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, Self.itemIDType]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL {
            return (item.url as NSURL).pasteboardPropertyList(forType: .fileURL)
        }
        if type == Self.itemIDType {
            return item.id.uuidString
        }
        return nil
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let thumbnailItem = NSUserInterfaceItemIdentifier("ThumbnailItem")
}

final class ThumbnailCollectionViewItem: NSCollectionViewItem {
    private let thumbImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var currentURL: URL?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6

        thumbImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbImageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(thumbImageView)
        container.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            thumbImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            thumbImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            thumbImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            thumbImageView.heightAnchor.constraint(equalToConstant: 105),

            nameLabel.topAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4),
        ])

        view = container
        imageView = thumbImageView
        textField = nameLabel
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    private func updateSelectionAppearance() {
        view.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
            : NSColor.clear.cgColor
    }

    func configure(with item: ImageItem) {
        nameLabel.stringValue = item.displayName
        thumbImageView.image = nil
        currentURL = item.url
        ThumbnailCache.shared.thumbnail(for: item.url, maxPixelSize: 320) { [weak self] loaded in
            guard self?.currentURL == item.url else { return }
            self?.thumbImageView.image = loaded
        }
    }
}

/// AppKit dataSource/delegate for one review column's collection view.
/// Owned externally (by the SwiftUI view) so keyboard shortcuts outside the
/// representable (Cmd+A / Cmd+C) can still reach the live NSCollectionView
/// and current selection.
final class ImageGridCoordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let kind: ReviewColumnKind
    var items: [ImageItem] = []
    var onSelectionChanged: (Set<UUID>) -> Void = { _ in }
    var onDropReclassify: ([UUID]) -> Void = { _ in }
    weak var collectionView: NSCollectionView?
    private(set) var selectedIDs: Set<UUID> = []

    init(kind: ReviewColumnKind) {
        self.kind = kind
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: .thumbnailItem, for: indexPath) as! ThumbnailCollectionViewItem
        cell.configure(with: items[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard items.indices.contains(indexPath.item) else { return nil }
        return DraggableImageReference(item: items[indexPath.item])
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        reportSelection(collectionView)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        reportSelection(collectionView)
    }

    private func reportSelection(_ collectionView: NSCollectionView) {
        let ids = Set(collectionView.selectionIndexPaths.compactMap { items.indices.contains($0.item) ? items[$0.item].id : nil })
        selectedIDs = ids
        onSelectionChanged(ids)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        dropOperation.pointee = .on
        return .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        var ids: [UUID] = []
        draggingInfo.enumerateDraggingItems(options: [], for: collectionView, classes: [NSPasteboardItem.self], searchOptions: [:]) { draggingItem, _, _ in
            if let pasteboardItem = draggingItem.item as? NSPasteboardItem,
               let string = pasteboardItem.string(forType: DraggableImageReference.itemIDType),
               let uuid = UUID(uuidString: string) {
                ids.append(uuid)
            }
        }
        guard !ids.isEmpty else { return false }
        onDropReclassify(ids)
        return true
    }
}

/// NSCollectionView wrapped for SwiftUI. Gives us, for free, rubber-band
/// (click-drag) multi-select and native drag-out to Finder / between the two
/// review columns, none of which SwiftUI's own grids support directly.
struct ImageGridView: NSViewRepresentable {
    let coordinator: ImageGridCoordinator
    let items: [ImageItem]

    func makeCoordinator() -> ImageGridCoordinator {
        coordinator
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 135)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [NSColor.black.withAlphaComponent(0.2)]
        collectionView.register(ThumbnailCollectionViewItem.self, forItemWithIdentifier: .thumbnailItem)
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.registerForDraggedTypes([DraggableImageReference.itemIDType])
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.black.withAlphaComponent(0.2)
        scrollView.documentView = collectionView

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])

        context.coordinator.collectionView = collectionView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.items = items
        guard let collectionView = context.coordinator.collectionView else { return }
        let previousSelection = context.coordinator.selectedIDs
        collectionView.reloadData()
        let indexPaths = Set(
            items.enumerated().compactMap { index, item in
                previousSelection.contains(item.id) ? IndexPath(item: index, section: 0) : nil
            }
        )
        collectionView.selectionIndexPaths = indexPaths
    }
}

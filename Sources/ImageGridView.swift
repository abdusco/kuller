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
    let cropRects: [UUID: NormalizedRect]

    init(item: ImageItem, cropRects: [UUID: NormalizedRect]) {
        self.item = item
        self.cropRects = cropRects
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, Self.itemIDType]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL {
            // NSPasteboardWriting is queried synchronously by AppKit at drag
            // time, so this resolves (and, on a cache miss, renders) the
            // crop synchronously rather than via the async API used by
            // Quick Look/copy.
            let url = CroppedImageRenderer.resolvedURLSync(for: item, cropRects: cropRects)
            return (url as NSURL).pasteboardPropertyList(forType: .fileURL)
        }
        if type == Self.itemIDType {
            return item.id.uuidString
        }
        return nil
    }
}

/// Grid geometry, shared with the window-sizing code so the review window's
/// minimum size can be derived from it rather than guessed.
enum ImageGridMetrics {
    static let itemSize = NSSize(width: 156, height: 136)
    static let spacing: CGFloat = 14
    static let inset: CGFloat = 16
    /// Room for exactly one column of thumbnails, plus the vertical scroller.
    static let minimumColumnWidth = itemSize.width + inset * 2 + 16
}

private extension NSUserInterfaceItemIdentifier {
    static let thumbnailItem = NSUserInterfaceItemIdentifier("ThumbnailItem")
}

final class ThumbnailCollectionViewItem: NSCollectionViewItem {
    /// Rounded, clipping tile that holds the picture and draws the selection
    /// ring — kept separate from the cell's own view so the filename below
    /// stays outside the ring, the way Finder's icon view lays out.
    private let tile = NSView()
    private let thumbImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let cropBadge = NSImageView()
    private let deleteButton = NSButton()
    private var currentURL: URL?
    private var onDelete: (() -> Void)?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        tile.wantsLayer = true
        tile.layer?.cornerRadius = 8
        tile.layer?.cornerCurve = .continuous
        tile.layer?.masksToBounds = true
        tile.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        tile.layer?.borderColor = NSColor.controlAccentColor.cgColor
        tile.translatesAutoresizingMaskIntoConstraints = false

        thumbImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbImageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        tile.addSubview(thumbImageView)
        container.addSubview(tile)
        container.addSubview(nameLabel)

        cropBadge.wantsLayer = true
        cropBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        cropBadge.layer?.cornerRadius = 8
        cropBadge.image = NSImage(systemSymbolName: "crop", accessibilityDescription: "Cropped")
        cropBadge.contentTintColor = .white
        cropBadge.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        cropBadge.isHidden = true
        cropBadge.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(cropBadge)

        // Only shown on virtual copies (see AppState.insertVirtualCopy) —
        // bottom-trailing, opposite cropBadge's bottom-leading, so "what is
        // this" and "discard it" never overlap.
        deleteButton.bezelStyle = .regularSquare
        deleteButton.isBordered = false
        deleteButton.imagePosition = .imageOnly
        deleteButton.image = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "Delete crop")
        deleteButton.contentTintColor = .white
        deleteButton.wantsLayer = true
        deleteButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        deleteButton.layer?.cornerRadius = 9
        deleteButton.isHidden = true
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        tile.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            tile.topAnchor.constraint(equalTo: container.topAnchor),
            tile.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tile.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tile.heightAnchor.constraint(equalToConstant: 112),

            thumbImageView.topAnchor.constraint(equalTo: tile.topAnchor, constant: 5),
            thumbImageView.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 5),
            thumbImageView.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -5),
            thumbImageView.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -5),

            cropBadge.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -4),
            cropBadge.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 4),
            cropBadge.widthAnchor.constraint(equalToConstant: 16),
            cropBadge.heightAnchor.constraint(equalToConstant: 16),

            deleteButton.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -4),
            deleteButton.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -4),
            deleteButton.widthAnchor.constraint(equalToConstant: 18),
            deleteButton.heightAnchor.constraint(equalToConstant: 18),

            nameLabel.topAnchor.constraint(equalTo: tile.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])

        view = container
        imageView = thumbImageView
        textField = nameLabel
        updateSelectionAppearance()
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    private func updateSelectionAppearance() {
        tile.layer?.borderWidth = isSelected ? 2.5 : 0
        tile.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
            : NSColor.white.withAlphaComponent(0.06).cgColor
        nameLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
    }

    func configure(with item: ImageItem, cropRect: NormalizedRect?, onDelete: @escaping () -> Void) {
        nameLabel.stringValue = item.displayName
        thumbImageView.image = nil
        currentURL = item.url
        self.onDelete = onDelete
        cropBadge.isHidden = !item.isVirtualCopy
        deleteButton.isHidden = !item.isVirtualCopy
        ThumbnailCache.shared.thumbnail(for: item.url) { [weak self] loaded in
            guard self?.currentURL == item.url else { return }
            self?.thumbImageView.image = loaded?.cropped(to: cropRect)
        }
    }

    @objc private func deleteTapped() {
        onDelete?()
    }
}

/// Activate the column even when a click doesn't change its selection.
final class ReviewCollectionView: NSCollectionView {
    var onFocus: () -> Void = {}

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus() }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        onFocus()
        super.mouseDown(with: event)
    }
}

/// AppKit dataSource/delegate for one review column's collection view.
/// Owned externally (by the SwiftUI view) so keyboard shortcuts outside the
/// representable (Cmd+A / Cmd+C) can still reach the live NSCollectionView
/// and current selection.
final class ImageGridCoordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let kind: ReviewColumnKind
    var items: [ImageItem] = []
    var cropRects: [UUID: NormalizedRect] = [:]
    var onFocus: () -> Void = {}
    var onSelectionChanged: (Set<UUID>) -> Void = { _ in }
    var onDropReclassify: ([UUID]) -> Void = { _ in }
    var onDeleteVirtualCopy: (ImageItem) -> Void = { _ in }
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
        let item = items[indexPath.item]
        cell.configure(with: item, cropRect: cropRects[item.id], onDelete: { [weak self] in self?.onDeleteVirtualCopy(item) })
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard items.indices.contains(indexPath.item) else { return nil }
        return DraggableImageReference(item: items[indexPath.item], cropRects: cropRects)
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
    var cropRects: [UUID: NormalizedRect] = [:]

    func makeCoordinator() -> ImageGridCoordinator {
        coordinator
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = ImageGridMetrics.itemSize
        layout.minimumInteritemSpacing = ImageGridMetrics.spacing
        layout.minimumLineSpacing = ImageGridMetrics.spacing
        layout.sectionInset = NSEdgeInsets(
            top: 4,
            left: ImageGridMetrics.inset,
            bottom: ImageGridMetrics.inset,
            right: ImageGridMetrics.inset
        )

        let collectionView = ReviewCollectionView()
        collectionView.onFocus = { [weak coordinator = context.coordinator] in
            coordinator?.onFocus()
        }
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        // Fully transparent: ReviewView paints one translucent backdrop behind
        // the whole screen. Tinting here too would stack a second layer over
        // it, making the grids visibly darker than the toolbar and headers.
        collectionView.backgroundColors = [.clear]
        collectionView.register(ThumbnailCollectionViewItem.self, forItemWithIdentifier: .thumbnailItem)
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.registerForDraggedTypes([DraggableImageReference.itemIDType])
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = collectionView

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            collectionView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
        ])

        context.coordinator.collectionView = collectionView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.items = items
        context.coordinator.cropRects = cropRects
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

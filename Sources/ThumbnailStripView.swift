import AppKit
import SwiftUI

private let stripGap: CGFloat = 8

struct ThumbnailStripView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ThumbnailStripTable(
            items: appState.items,
            currentID: appState.currentItem?.id,
            decisions: appState.decisions,
            cropRects: appState.cropRects,
            onSelect: { appState.jumpTo($0) },
            onDelete: { appState.removeVirtualCopy($0) }
        )
        .padding(stripGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
    }
}

/// AppKit owns row placement and scrolling. SwiftUI's LazyVStack could loop
/// indefinitely placing variable-height rows during animated scrollTo calls.
struct ThumbnailStripTable: NSViewRepresentable {
    let items: [ImageItem]
    let currentID: UUID?
    let decisions: [UUID: Decision]
    let cropRects: [UUID: NormalizedRect]
    let onSelect: (ImageItem) -> Void
    let onDelete: (ImageItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.intercellSpacing = NSSize(width: 0, height: stripGap)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        table.usesAutomaticRowHeights = false
        table.allowsEmptySelection = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("thumbnail"))
        column.minWidth = 1
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: NSTableView?
        private var content: ThumbnailStripTable?
        private var pendingRatios: Set<URL> = []
        private var updating = false
        private var lastScrolledID: UUID?

        func update(_ content: ThumbnailStripTable) {
            guard let table else { return }
            let itemsChanged = self.content?.items != content.items
            let cropsChanged = self.content?.cropRects != content.cropRects
            self.content = content
            updating = true
            defer { updating = false }
            if itemsChanged {
                table.reloadData()
            } else if cropsChanged {
                table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: content.items.indices))
            }
            if let index = content.items.firstIndex(where: { $0.id == content.currentID }) {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                if lastScrolledID != content.currentID || itemsChanged {
                    // No animation or SwiftUI layout transaction to overlap
                    // with the next key repeat or an arriving thumbnail.
                    table.scrollRowToVisible(index)
                    lastScrolledID = content.currentID
                }
            } else {
                table.deselectAll(nil)
                lastScrolledID = nil
            }
            refreshVisibleRows()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            content?.items.count ?? 0
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard let content, content.items.indices.contains(row) else { return 90 }
            let item = content.items[row]
            let ratio = ThumbnailCache.shared.cachedAspectRatio(for: item.url)
            if ratio == nil, pendingRatios.insert(item.url).inserted {
                ThumbnailCache.shared.aspectRatio(for: item.url) { [weak self] _ in
                    guard let self, let table = self.table, let content = self.content else { return }
                    self.pendingRatios.remove(item.url)
                    let rows = IndexSet(content.items.indices.filter { content.items[$0].url == item.url })
                    table.noteHeightOfRows(withIndexesChanged: rows)
                }
            }
            var aspect = ratio ?? 4.0 / 3.0
            if let crop = content.cropRects[item.id], crop.width > 0, crop.height > 0 {
                aspect *= crop.width / crop.height
            }
            let width = tableView.tableColumns.first?.width ?? 124
            return max(1, width / aspect)
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let content, content.items.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("thumbnailCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ThumbnailStripCell
                ?? ThumbnailStripCell(frame: .zero)
            cell.identifier = identifier
            configure(cell, at: row)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table, let content,
                  content.items.indices.contains(table.selectedRow) else { return }
            content.onSelect(content.items[table.selectedRow])
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let table, let content else { return }
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: content.items.indices))
        }

        private func refreshVisibleRows() {
            guard let table else { return }
            let rows = table.rows(in: table.visibleRect)
            guard rows.location != NSNotFound, rows.length > 0 else { return }
            for row in rows.location..<NSMaxRange(rows) {
                if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ThumbnailStripCell {
                    configure(cell, at: row)
                }
            }
        }

        private func configure(_ cell: ThumbnailStripCell, at row: Int) {
            guard let content, content.items.indices.contains(row) else { return }
            let item = content.items[row]
            cell.configure(item: item, isCurrent: item.id == content.currentID,
                           decision: content.decisions[item.id], cropRect: content.cropRects[item.id],
                           onDelete: { content.onDelete(item) })
        }
    }
}

/// Only visible cells load thumbnails. A request token also protects reused
/// cells and virtual copies sharing the same source URL from stale callbacks.
final class ThumbnailStripCell: NSTableCellView {
    private let thumbnail = NSImageView()
    private let decisionBadge = NSImageView()
    private let cropBadge = NSImageView()
    private let deleteButton = NSButton()
    private var itemID: UUID?
    private var cropRect: NormalizedRect?
    private var requestID = UUID()
    private var onDelete: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        thumbnail.imageScaling = .scaleAxesIndependently
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnail)
        for badge in [decisionBadge, cropBadge] {
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.imageScaling = .scaleProportionallyUpOrDown
            addSubview(badge)
        }
        cropBadge.image = NSImage(systemSymbolName: "crop", accessibilityDescription: "Cropped")
        cropBadge.contentTintColor = .white
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "Delete crop")
        deleteButton.contentTintColor = .white
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteButton)
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnail.topAnchor.constraint(equalTo: topAnchor),
            thumbnail.bottomAnchor.constraint(equalTo: bottomAnchor),
            decisionBadge.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            decisionBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            decisionBadge.widthAnchor.constraint(equalToConstant: 16),
            decisionBadge.heightAnchor.constraint(equalToConstant: 16),
            cropBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            cropBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            cropBadge.widthAnchor.constraint(equalToConstant: 16),
            cropBadge.heightAnchor.constraint(equalToConstant: 16),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            deleteButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            deleteButton.widthAnchor.constraint(equalToConstant: 18),
            deleteButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: ImageItem, isCurrent: Bool, decision: Decision?, cropRect: NormalizedRect?, onDelete: @escaping () -> Void) {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = isCurrent ? 3 : 0
        toolTip = item.displayName
        decisionBadge.isHidden = decision == nil
        decisionBadge.image = NSImage(systemSymbolName: decision == .pick ? "checkmark.circle.fill" : "xmark.circle.fill",
                                     accessibilityDescription: decision == .pick ? "Pick" : "Reject")
        decisionBadge.contentTintColor = decision == .pick ? .systemGreen : .systemRed
        cropBadge.isHidden = !item.isVirtualCopy
        deleteButton.isHidden = !item.isVirtualCopy
        self.onDelete = onDelete
        guard itemID != item.id || self.cropRect != cropRect else { return }
        itemID = item.id
        self.cropRect = cropRect
        let token = UUID()
        requestID = token
        thumbnail.image = nil
        ThumbnailCache.shared.thumbnail(for: item.url) { [weak self] image in
            guard let self, self.requestID == token else { return }
            self.thumbnail.image = image?.cropped(to: cropRect)
        }
    }

    @objc private func deleteTapped() { onDelete?() }
}

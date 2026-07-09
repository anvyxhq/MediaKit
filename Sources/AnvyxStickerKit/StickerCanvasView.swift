//
//  StickerCanvasView.swift
//  StickerKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

/// A container that hosts ``TransformableItemView`` items: manages single
/// selection, add/remove, save/restore of placements, and **flattening the
/// whole canvas to a `UIImage`** (chrome hidden) for export — e.g. stamping the
/// result onto a PDF page via PDFKitWrapper, or converting via ImageKit.
open class StickerCanvasView: UIView, TransformableItemDelegate {

    public private(set) var items: [TransformableItemView] = []
    public private(set) weak var selectedItem: TransformableItemView?

    /// Called after any add / remove / move / scale / rotate — persist / sync undo here.
    public var onChange: (() -> Void)?

    private let history = UndoHistory<[StickerItemDescriptor]>()
    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    /// Alignment guides shown while an item snaps to a canvas mid-line.
    private lazy var verticalGuide = makeGuide()
    private lazy var horizontalGuide = makeGuide()

    private func makeGuide() -> UIView {
        let v = UIView()
        v.backgroundColor = .systemPink
        v.isUserInteractionEnabled = false
        v.isHidden = true
        addSubview(v)
        return v
    }

    private func layoutGuides() {
        verticalGuide.frame = CGRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
        horizontalGuide.frame = CGRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1)
    }

    // MARK: - Items

    public func add(_ item: TransformableItemView, at center: CGPoint? = nil) {
        recordUndo()
        item.delegate = self
        if let center { item.center = center }
        addSubview(item)
        items.append(item)
        select(item)
        onChange?()
    }

    public func remove(_ item: TransformableItemView) {
        recordUndo()
        item.removeFromSuperview()
        items.removeAll { $0 === item }
        if selectedItem === item { selectedItem = nil }
        onChange?()
    }

    public func select(_ item: TransformableItemView?) {
        selectedItem = item
        for i in items { i.isSelected = (i === item) }
    }

    public func deselectAll() { select(nil) }

    // MARK: - Save / restore placements

    /// Placement snapshots of all items, in z-order.
    public func snapshot() -> [TransformState] { items.map { $0.makeState() } }

    /// Re-apply placements by matching `id`. Content must already be recreated.
    public func restore(_ states: [TransformState]) {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for state in states { byID[state.id]?.apply(state) }
    }

    // MARK: - Undo / redo (history is a pure, testable UndoHistory)

    /// Full descriptors (content + placement) needed to rebuild the canvas.
    public func descriptors() -> [StickerItemDescriptor] {
        items.compactMap { item in
            guard let content = item.contentKind() else { return nil }
            return StickerItemDescriptor(id: item.id, content: content, state: item.makeState())
        }
    }

    /// Record an undo point immediately before a mutation.
    public func recordUndo() { history.record(descriptors()) }

    public func undo() {
        guard let descriptors = history.undo(current: descriptors()) else { return }
        rebuild(from: descriptors)
    }

    public func redo() {
        guard let descriptors = history.redo(current: descriptors()) else { return }
        rebuild(from: descriptors)
    }

    /// Recreate every item from descriptors (used by undo/redo and restore-with-content).
    public func rebuild(from descriptors: [StickerItemDescriptor]) {
        items.forEach { $0.removeFromSuperview() }
        items.removeAll()
        selectedItem = nil
        for descriptor in descriptors {
            let size = descriptor.state.size
            let frame = CGRect(origin: .zero, size: size)
            let item: TransformableItemView
            switch descriptor.content {
            case let .text(text, font, color):
                item = TextItemView(id: descriptor.id, text: text, font: font, textColor: color, frame: frame)
            case let .image(image):
                item = ImageItemView(id: descriptor.id, image: image, frame: frame)
            }
            item.delegate = self
            item.isSelected = false
            addSubview(item)
            items.append(item)
            item.apply(descriptor.state)
        }
        onChange?()
    }

    // MARK: - Flatten / export

    /// Render the canvas (selection chrome hidden) into an image at `scale`
    /// (0 = screen scale). Use this to burn stickers into a page or export.
    public func flattenedImage(scale: CGFloat = 0) -> UIImage {
        let previouslySelected = selectedItem
        deselectAll()
        let format = UIGraphicsImageRendererFormat()
        if scale > 0 { format.scale = scale }
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { ctx in
            layer.render(in: ctx.cgContext)
        }
        select(previouslySelected)
        return image
    }

    // MARK: - Tap-to-deselect on empty space

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if let point = touches.first?.location(in: self),
           hitTest(point, with: event) === self {
            deselectAll()
        }
    }

    // MARK: - TransformableItemDelegate

    public func itemDidSelect(_ item: TransformableItemView) { select(item) }
    public func itemDidBeginOperation(_ item: TransformableItemView) { recordUndo() }
    public func itemDidChange(_ item: TransformableItemView) { onChange?() }
    public func itemDidRequestDelete(_ item: TransformableItemView) { remove(item) }
    public func itemDidEndOperation(_ item: TransformableItemView) {
        verticalGuide.isHidden = true
        horizontalGuide.isHidden = true
    }

    public func item(_ item: TransformableItemView, didUpdateSnap snapX: Bool, snapY: Bool) {
        layoutGuides()
        verticalGuide.isHidden = !snapX
        horizontalGuide.isHidden = !snapY
        if snapX { bringSubviewToFront(verticalGuide) }
        if snapY { bringSubviewToFront(horizontalGuide) }
    }
}

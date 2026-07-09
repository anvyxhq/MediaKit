//
//  SwiftUICanvas.swift
//  StickerKit
//
//  Created by AnhPT on 03/07/2026.
//

import SwiftUI
import UIKit

/// Owns a ``StickerCanvasView`` and exposes it to SwiftUI. Keep one as
/// `@StateObject` and drive it imperatively (add items, flatten, snapshot),
/// while ``StickerCanvas`` renders it.
///
/// ```swift
/// @StateObject private var canvas = StickerCanvasController()
///
/// var body: some View {
///     StickerCanvas(controller: canvas)
///     Button("Add") { canvas.addText("Hello") }
///     Button("Export") { let image = canvas.flattenedImage() /* stamp onto PDF */ }
/// }
/// ```
@MainActor
public final class StickerCanvasController: ObservableObject {
    public let canvas = StickerCanvasView()

    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

    public init() {
        canvas.onChange = { [weak self] in
            guard let self else { return }
            self.canUndo = self.canvas.canUndo
            self.canRedo = self.canvas.canRedo
        }
    }

    public func undo() { canvas.undo() }
    public func redo() { canvas.redo() }

    @discardableResult
    public func addText(
        _ text: String,
        font: UIFont = .systemFont(ofSize: 24),
        color: UIColor = .label,
        size: CGSize = CGSize(width: 160, height: 60),
        at center: CGPoint? = nil
    ) -> TextItemView {
        let item = TextItemView(text: text, font: font, textColor: color,
                                frame: CGRect(origin: .zero, size: size))
        canvas.add(item, at: center ?? canvasCenter)
        return item
    }

    @discardableResult
    public func addImage(
        _ image: UIImage,
        size: CGSize? = nil,
        at center: CGPoint? = nil
    ) -> ImageItemView {
        let resolved = size ?? image.size
        let item = ImageItemView(image: image, frame: CGRect(origin: .zero, size: resolved))
        canvas.add(item, at: center ?? canvasCenter)
        return item
    }

    public func flattenedImage(scale: CGFloat = 0) -> UIImage { canvas.flattenedImage(scale: scale) }
    public func snapshot() -> [TransformState] { canvas.snapshot() }
    public func deselectAll() { canvas.deselectAll() }

    private var canvasCenter: CGPoint {
        CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
    }
}

/// SwiftUI wrapper around ``StickerCanvasView`` — reuses the UIKit gesture engine
/// (drag/pinch/rotate + corner handle) unchanged.
public struct StickerCanvas: UIViewRepresentable {
    @ObservedObject private var controller: StickerCanvasController

    public init(controller: StickerCanvasController) {
        self.controller = controller
    }

    public func makeUIView(context: Context) -> StickerCanvasView {
        controller.canvas
    }

    public func updateUIView(_ uiView: StickerCanvasView, context: Context) {}
}

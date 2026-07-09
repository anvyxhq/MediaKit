//
//  PureSwiftUICanvas.swift
//  StickerKit
//
//  Created by AnhPT on 03/07/2026.
//
//  A pure-SwiftUI implementation of the transformable-item canvas (no UIKit
//  gesture engine). Prefer the UIViewRepresentable bridge (`StickerCanvas`) when
//  you want the exact UIKit behavior; use this when you want a native SwiftUI
//  view tree. Requires iOS 17 for MagnifyGesture / RotateGesture.

import SwiftUI
import UIKit

@MainActor
public final class SwiftUIStickerItem: ObservableObject, Identifiable {
    public enum Content {
        case text(String, font: Font, color: Color)
        case image(UIImage)
    }

    public let id: String
    public let content: Content
    @Published public var center: CGPoint
    @Published public var size: CGSize
    @Published public var scale: CGFloat
    @Published public var rotation: Angle
    public var minScale: CGFloat = 0.3
    public var maxScale: CGFloat = 6

    public init(id: String = UUID().uuidString, content: Content, center: CGPoint,
                size: CGSize, scale: CGFloat = 1, rotation: Angle = .zero) {
        self.id = id; self.content = content; self.center = center
        self.size = size; self.scale = scale; self.rotation = rotation
    }

    /// Codable placement snapshot (shared with the UIKit path).
    public var state: TransformState {
        TransformState(id: id, center: center, size: size, scale: scale, rotation: CGFloat(rotation.radians))
    }
    public func apply(_ s: TransformState) {
        center = s.center; size = s.size; scale = s.scale; rotation = .radians(Double(s.rotation))
    }
    func clampScale() { scale = min(max(scale, minScale), maxScale) }
}

@MainActor
public final class SwiftUIStickerStore: ObservableObject {
    @Published public var items: [SwiftUIStickerItem] = []
    @Published public var selectedID: String?

    public init() {}

    @discardableResult
    public func addText(_ text: String, font: Font = .system(size: 24), color: Color = .primary,
                        center: CGPoint, size: CGSize = CGSize(width: 160, height: 60)) -> SwiftUIStickerItem {
        let item = SwiftUIStickerItem(content: .text(text, font: font, color: color), center: center, size: size)
        items.append(item); selectedID = item.id; return item
    }

    @discardableResult
    public func addImage(_ image: UIImage, center: CGPoint, size: CGSize? = nil) -> SwiftUIStickerItem {
        let item = SwiftUIStickerItem(content: .image(image), center: center, size: size ?? image.size)
        items.append(item); selectedID = item.id; return item
    }

    public func remove(_ id: String) {
        items.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    public func snapshot() -> [TransformState] { items.map(\.state) }

    public func restore(_ states: [TransformState]) {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        states.forEach { byID[$0.id]?.apply($0) }
    }

    /// Flatten the canvas to an image (selection chrome hidden) via `ImageRenderer`.
    public func flattenedImage(size: CGSize, scale: CGFloat = 0) -> UIImage? {
        let previous = selectedID
        selectedID = nil
        let renderer = ImageRenderer(content:
            SwiftUIStickerCanvas(store: self).frame(width: size.width, height: size.height)
        )
        renderer.scale = scale > 0 ? scale : UIScreen.main.scale
        let image = renderer.uiImage
        selectedID = previous
        return image
    }
}

public struct SwiftUIStickerCanvas: View {
    @ObservedObject private var store: SwiftUIStickerStore
    private let space = "StickerKit.canvas"

    public init(store: SwiftUIStickerStore) { self.store = store }

    public var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.selectedID = nil }
            ForEach(store.items) { item in
                StickerItemView(
                    item: item,
                    isSelected: store.selectedID == item.id,
                    space: space,
                    onSelect: { store.selectedID = item.id },
                    onDelete: { store.remove(item.id) }
                )
            }
        }
        .coordinateSpace(name: space)
    }
}

private struct StickerItemView: View {
    @ObservedObject var item: SwiftUIStickerItem
    let isSelected: Bool
    let space: String
    let onSelect: () -> Void
    let onDelete: () -> Void

    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var twist: Angle = .zero
    @State private var handleStart: (radius: CGFloat, angle: CGFloat, scale: CGFloat, rotation: Angle)?

    private var effScale: CGFloat { item.scale * pinch }
    private var effRotation: Angle { item.rotation + twist }
    private var effCenter: CGPoint { CGPoint(x: item.center.x + drag.width, y: item.center.y + drag.height) }

    var body: some View {
        content
            .frame(width: item.size.width, height: item.size.height)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2).stroke(Color.blue, lineWidth: 1 / effScale)
                }
            }
            .overlay(alignment: .topLeading) { if isSelected { deleteButton } }
            .overlay(alignment: .bottomTrailing) { if isSelected { handle } }
            .scaleEffect(effScale)
            .rotationEffect(effRotation)
            .position(effCenter)
            .gesture(bodyGesture)
            .onTapGesture { onSelect() }
    }

    @ViewBuilder private var content: some View {
        switch item.content {
        case let .text(text, font, color):
            Text(text).font(font).foregroundStyle(color).multilineTextAlignment(.center)
        case let .image(image):
            Image(uiImage: image).resizable().scaledToFit()
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22)).foregroundStyle(.red)
                .background(Circle().fill(.white))
        }
        .scaleEffect(1 / effScale)
        .offset(x: -10, y: -10)
    }

    private var handle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
            .font(.system(size: 22)).foregroundStyle(.blue)
            .background(Circle().fill(.white))
            .scaleEffect(1 / effScale)
            .offset(x: 10, y: 10)
            .highPriorityGesture(handleGesture)
    }

    private var bodyGesture: some Gesture {
        let move = DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                item.center.x += value.translation.width
                item.center.y += value.translation.height
            }
        let magnify = MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in item.scale *= value.magnification; item.clampScale() }
        let rotate = RotateGesture()
            .updating($twist) { value, state, _ in state = value.rotation }
            .onEnded { value in item.rotation += value.rotation }
        return move.simultaneously(with: magnify).simultaneously(with: rotate)
    }

    private var handleGesture: some Gesture {
        DragGesture(coordinateSpace: .named(space))
            .onChanged { value in
                let dx = value.location.x - item.center.x
                let dy = value.location.y - item.center.y
                let radius = max(1, hypot(dx, dy))
                let angle = atan2(dy, dx)
                if handleStart == nil {
                    handleStart = (radius, angle, item.scale, item.rotation)
                }
                guard let start = handleStart else { return }
                item.scale = min(max(start.scale * radius / start.radius, item.minScale), item.maxScale)
                item.rotation = start.rotation + .radians(Double(angle - start.angle))
            }
            .onEnded { _ in handleStart = nil }
    }
}

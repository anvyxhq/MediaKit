//
//  StickerHistory.swift
//  StickerKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

/// Enough to recreate a canvas item on undo/redo.
public enum StickerContentKind {
    case text(String, font: UIFont, color: UIColor)
    case image(UIImage)
}

/// A UI-independent snapshot of one item (content + placement).
public struct StickerItemDescriptor {
    public let id: String
    public let content: StickerContentKind
    public let state: TransformState

    public init(id: String, content: StickerContentKind, state: TransformState) {
        self.id = id; self.content = content; self.state = state
    }
}

/// A pure, generic undo/redo stack (single responsibility: history management).
/// The owner supplies its current state and applies the returned one, so this
/// is fully unit-testable without any view.
public final class UndoHistory<State> {
    private var undoStack: [State] = []
    private var redoStack: [State] = []

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public init() {}

    /// Record `current` as an undo point (call right before a mutation).
    public func record(_ current: State) {
        undoStack.append(current)
        redoStack.removeAll()
    }

    public func undo(current: State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    public func redo(current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    public func clear() {
        undoStack.removeAll(); redoStack.removeAll()
    }
}

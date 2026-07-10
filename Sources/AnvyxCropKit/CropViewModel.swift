//
//  CropViewModel.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit
import Observation

/// A normalized snapshot of the crop geometry, independent of view size — safe
/// to persist and restore.
public struct CropState: Codable, Equatable, Sendable {
    public var normalizedBox: CGRect      // crop box as a fraction of the image frame
    public var zoomScale: CGFloat
    public var normalizedOffset: CGPoint  // content offset / content size
    public var rotationAngle: CGFloat

    public init(normalizedBox: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                zoomScale: CGFloat = 1,
                normalizedOffset: CGPoint = .zero,
                rotationAngle: CGFloat = 0) {
        self.normalizedBox = normalizedBox; self.zoomScale = zoomScale
        self.normalizedOffset = normalizedOffset; self.rotationAngle = rotationAngle
    }
}

/// The full, UI-independent editor state (the "document" being edited).
public struct CropDocument: Sendable {
    public var workingImage: UIImage
    public var crop: CropState
    public var adjustments: ImageAdjustments
    public var colorFilter: ColorFilter
    public var filterIntensity: CGFloat
    public var aspectRatio: CropAspectRatio
    public var shape: CropShape

    public init(workingImage: UIImage, crop: CropState = .init(),
                adjustments: ImageAdjustments = .none, colorFilter: ColorFilter = .none,
                filterIntensity: CGFloat = 1, aspectRatio: CropAspectRatio = .free,
                shape: CropShape = .rectangle) {
        self.workingImage = workingImage; self.crop = crop
        self.adjustments = adjustments; self.colorFilter = colorFilter
        self.filterIntensity = filterIntensity; self.aspectRatio = aspectRatio; self.shape = shape
    }
}

/// Pure, UIKit-free undo/redo state machine for the cropper (single
/// responsibility: manage the history of ``CropDocument`` states). The view
/// supplies its current document and applies the returned one — so this logic
/// is fully unit-testable without any view.
@Observable
@MainActor
public final class CropViewModel {

    public private(set) var canUndo = false
    public private(set) var canRedo = false

    private var undoStack: [CropDocument] = [] { didSet { canUndo = !undoStack.isEmpty } }
    private var redoStack: [CropDocument] = [] { didSet { canRedo = !redoStack.isEmpty } }

    public init() {}

    /// Record `current` as an undo point (call right before a mutation).
    public func record(_ current: CropDocument) {
        undoStack.append(current)
        redoStack.removeAll()
    }

    /// Pop the last undo state; `current` is pushed onto the redo stack.
    public func undo(current: CropDocument) -> CropDocument? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Pop the last redo state; `current` is pushed back onto the undo stack.
    public func redo(current: CropDocument) -> CropDocument? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    public func clearHistory() {
        undoStack.removeAll(); redoStack.removeAll()
    }
}

//
//  TransformableItemView.swift
//  StickerKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

/// Callbacks for a ``TransformableItemView``.
public protocol TransformableItemDelegate: AnyObject {
    func itemDidSelect(_ item: TransformableItemView)
    func itemDidBeginOperation(_ item: TransformableItemView)
    func itemDidChange(_ item: TransformableItemView)
    func itemDidEndOperation(_ item: TransformableItemView)
    func itemDidRequestDelete(_ item: TransformableItemView)
    /// Live snap state while dragging — the canvas uses this to show alignment guides.
    func item(_ item: TransformableItemView, didUpdateSnap snapX: Bool, snapY: Bool)
}

public extension TransformableItemDelegate {
    func itemDidSelect(_ item: TransformableItemView) {}
    func itemDidBeginOperation(_ item: TransformableItemView) {}
    func itemDidChange(_ item: TransformableItemView) {}
    func itemDidEndOperation(_ item: TransformableItemView) {}
    func itemDidRequestDelete(_ item: TransformableItemView) {}
    func item(_ item: TransformableItemView, didUpdateSnap snapX: Bool, snapY: Bool) {}
}

/// A serializable snapshot of an item's placement (for save / restore).
/// The item's *content* (text, image…) is restored separately by the subclass.
public struct TransformState: Codable, Equatable {
    public var id: String
    public var center: CGPoint
    public var size: CGSize
    public var scale: CGFloat
    public var rotation: CGFloat

    public init(id: String, center: CGPoint, size: CGSize, scale: CGFloat, rotation: CGFloat) {
        self.id = id; self.center = center; self.size = size; self.scale = scale; self.rotation = rotation
    }
}

/// A gesture-editable canvas item: **drag to move, pinch to scale, rotate with
/// two fingers, or use the corner handle to scale+rotate together**; a delete
/// button removes it, double-tap resets. Movement is applied to `center`
/// (superview space) while scale/rotation live in `transform` around the center,
/// so finger tracking is correct at any rotation.
///
/// For a smooth, "pro" feel it **snaps** rotation to 45° steps and the center to
/// the canvas mid-lines, with haptic feedback. Subclass and set ``content``.
open class TransformableItemView: UIView, UIGestureRecognizerDelegate {

    public let id: String
    public weak var delegate: TransformableItemDelegate?

    public var minScale: CGFloat = 0.4
    public var maxScale: CGFloat = 6.0
    public var gesturesEnabled = true

    // Snapping / polish
    public var snapsRotation = true
    public var snapsPosition = true
    public var rotationSnapThreshold: CGFloat = .pi / 36   // 5°
    public var positionSnapThreshold: CGFloat = 12

    public var content: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let content { borderView.insertSubview(content, at: 0); setNeedsLayout() }
        }
    }

    public private(set) var scale: CGFloat = 1
    public private(set) var rotation: CGFloat = 0
    public private(set) var isFlipped = false

    public var isSelected = false { didSet { updateChromeVisibility() } }

    // Chrome
    private let borderView = UIView()
    private let handle = UIImageView()
    private let deleteButton = UIButton(type: .system)
    private let inset: CGFloat = 10

    // Feedback + snap state
    private let haptic = UISelectionFeedbackGenerator()
    private var isRotationSnapped = false
    private var snapX = false
    private var snapY = false

    // Gesture scratch
    private var initialCenter: CGPoint = .zero
    private var handleInitialRadius: CGFloat = 1
    private var handleInitialAngle: CGFloat = 0
    private var handleInitialScale: CGFloat = 1
    private var handleInitialRotation: CGFloat = 0

    public init(id: String = UUID().uuidString, frame: CGRect) {
        self.id = id
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    private func setUp() {
        borderView.layer.borderColor = UIColor.systemBlue.cgColor
        borderView.layer.borderWidth = 1
        borderView.isUserInteractionEnabled = true
        addSubview(borderView)

        handle.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
        handle.tintColor = .systemBlue
        handle.backgroundColor = .white
        handle.layer.cornerRadius = 12
        handle.isUserInteractionEnabled = true
        addSubview(handle)

        deleteButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        deleteButton.tintColor = .systemRed
        deleteButton.backgroundColor = .white
        deleteButton.layer.cornerRadius = 12
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        addSubview(deleteButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        let cornerPan = UIPanGestureRecognizer(target: self, action: #selector(handleCornerPan))
        [tap, doubleTap, pinch, rotate, pan].forEach { $0.delegate = self; addGestureRecognizer($0) }
        cornerPan.delegate = self
        handle.addGestureRecognizer(cornerPan)
        pan.require(toFail: cornerPan)

        isSelected = true
    }

    // MARK: - Layout

    open override func layoutSubviews() {
        super.layoutSubviews()
        borderView.frame = bounds.insetBy(dx: inset, dy: inset)
        content?.frame = borderView.bounds
        let s: CGFloat = 24
        handle.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        deleteButton.bounds = handle.bounds
        handle.center = CGPoint(x: borderView.frame.maxX, y: borderView.frame.maxY)
        deleteButton.center = CGPoint(x: borderView.frame.minX, y: borderView.frame.minY)
        applyInverseChromeScale()
    }

    /// Expand the touch target for the small corner handle / delete button.
    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if isSelected {
            let pad: CGFloat = 22 / scale
            if handle.frame.insetBy(dx: -pad, dy: -pad).contains(point) { return true }
            if deleteButton.frame.insetBy(dx: -pad, dy: -pad).contains(point) { return true }
        }
        return super.point(inside: point, with: event)
    }

    // MARK: - Transform

    private func updateTransform() {
        transform = CGAffineTransform.identity.scaledBy(x: scale, y: scale).rotated(by: rotation)
        applyInverseChromeScale()
        delegate?.itemDidChange(self)
    }

    private func applyInverseChromeScale() {
        let inv = 1 / scale
        handle.transform = CGAffineTransform(scaleX: inv, y: inv)
        deleteButton.transform = CGAffineTransform(scaleX: inv, y: inv)
        borderView.layer.borderWidth = inv
    }

    private func clamped(_ value: CGFloat) -> CGFloat { min(max(value, minScale), maxScale) }

    private func updateChromeVisibility() {
        borderView.layer.borderColor = (isSelected ? UIColor.systemBlue : UIColor.clear).cgColor
        handle.isHidden = !isSelected
        deleteButton.isHidden = !isSelected
    }

    // MARK: - Snapping

    /// Snap `rotation` to the nearest 45° when within threshold; haptic on entry.
    private func snapRotationIfNeeded() {
        guard snapsRotation else { return }
        let twoPi = CGFloat.pi * 2
        var r = rotation.truncatingRemainder(dividingBy: twoPi)
        if r < 0 { r += twoPi }
        let step = CGFloat.pi / 4
        let nearest = (r / step).rounded() * step
        if abs(r - nearest) < rotationSnapThreshold {
            rotation += (nearest - r)          // keep winding, land on the snap angle
            if !isRotationSnapped { haptic.selectionChanged(); isRotationSnapped = true }
        } else {
            isRotationSnapped = false
        }
    }

    /// Snap a proposed center to the canvas mid-lines; haptic + guide on entry.
    private func snappedCenter(_ proposed: CGPoint) -> CGPoint {
        guard snapsPosition, let canvas = superview else { return proposed }
        var c = proposed
        let nx = abs(c.x - canvas.bounds.midX) < positionSnapThreshold
        let ny = abs(c.y - canvas.bounds.midY) < positionSnapThreshold
        if nx { c.x = canvas.bounds.midX }
        if ny { c.y = canvas.bounds.midY }
        if (nx && !snapX) || (ny && !snapY) { haptic.selectionChanged() }
        snapX = nx; snapY = ny
        delegate?.item(self, didUpdateSnap: nx, snapY: ny)
        return c
    }

    private func clearSnapGuides() {
        snapX = false; snapY = false
        delegate?.item(self, didUpdateSnap: false, snapY: false)
    }

    // MARK: - Gestures

    @objc private func handleTap() {
        guard gesturesEnabled else { return }
        superview?.bringSubviewToFront(self)
        isSelected = true
        delegate?.itemDidSelect(self)
    }

    @objc private func handleDoubleTap() { resetTransform() }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard gesturesEnabled else { return }
        let t = g.translation(in: superview)
        switch g.state {
        case .began: initialCenter = center; haptic.prepare(); begin()
        case .changed:
            center = snappedCenter(CGPoint(x: initialCenter.x + t.x, y: initialCenter.y + t.y))
            delegate?.itemDidChange(self)
        case .ended, .cancelled: clearSnapGuides(); end()
        default: break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard gesturesEnabled else { return }
        if g.state == .began { haptic.prepare(); begin() }
        scale = clamped(scale * g.scale); g.scale = 1
        updateTransform()
        if g.state == .ended || g.state == .cancelled { end() }
    }

    @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
        guard gesturesEnabled else { return }
        if g.state == .began { haptic.prepare(); begin() }
        rotation += g.rotation; g.rotation = 0
        snapRotationIfNeeded()
        updateTransform()
        if g.state == .ended || g.state == .cancelled { end() }
    }

    /// Corner handle: derive scale + rotation from the vector center→touch.
    @objc private func handleCornerPan(_ g: UIPanGestureRecognizer) {
        guard gesturesEnabled, let superview else { return }
        let p = g.location(in: superview)
        let v = CGVector(dx: p.x - center.x, dy: p.y - center.y)
        let radius = max(1, sqrt(v.dx * v.dx + v.dy * v.dy))
        let angle = atan2(v.dy, v.dx)
        switch g.state {
        case .began:
            handleInitialRadius = radius
            handleInitialAngle = angle
            handleInitialScale = scale
            handleInitialRotation = rotation
            haptic.prepare(); begin()
        case .changed:
            scale = clamped(handleInitialScale * radius / handleInitialRadius)
            rotation = handleInitialRotation + (angle - handleInitialAngle)
            snapRotationIfNeeded()
            updateTransform()
        case .ended, .cancelled: end()
        default: break
        }
    }

    @objc private func deleteTapped() { delegate?.itemDidRequestDelete(self) }

    private func begin() {
        isSelected = true
        superview?.bringSubviewToFront(self)
        delegate?.itemDidBeginOperation(self)
    }
    private func end() { delegate?.itemDidEndOperation(self) }

    public func gestureRecognizer(_ g: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: - Actions

    /// Reset scale and rotation (keeps position). Fires on double-tap.
    public func resetTransform() {
        scale = 1; rotation = 0; isRotationSnapped = false
        updateTransform()
    }

    /// Mirror the content horizontally.
    public func flipHorizontally() {
        isFlipped.toggle()
        content?.transform = isFlipped ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    // MARK: - State (save / restore)

    public func makeState() -> TransformState {
        TransformState(id: id, center: center, size: bounds.size, scale: scale, rotation: rotation)
    }

    /// Content needed to recreate this item on undo/redo. Subclasses override.
    open func contentKind() -> StickerContentKind? { nil }

    public func apply(_ state: TransformState) {
        bounds.size = state.size
        center = state.center
        scale = state.scale
        rotation = state.rotation
        setNeedsLayout()
        updateTransform()
    }
}

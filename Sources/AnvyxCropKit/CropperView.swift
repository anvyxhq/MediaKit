//
//  CropperView.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

enum CropEdge: CaseIterable {
    case none, topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    var isActive: Bool { self != .none }

    /// The eight adjustable handles (excludes `.none`).
    static var handles: [CropEdge] { allCases.filter { $0.isActive } }

    var accessibilityLabel: String {
        switch self {
        case .none: return ""
        case .topLeft: return "Top left crop handle"
        case .top: return "Top crop handle"
        case .topRight: return "Top right crop handle"
        case .left: return "Left crop handle"
        case .right: return "Right crop handle"
        case .bottomLeft: return "Bottom left crop handle"
        case .bottom: return "Bottom crop handle"
        case .bottomRight: return "Bottom right crop handle"
        }
    }
}

/// A VoiceOver-adjustable proxy for one crop-box handle: increment enlarges the
/// box on that side, decrement shrinks it.
final class CropHandleAccessibilityElement: UIAccessibilityElement {
    private let onAdjust: (CGFloat) -> Void
    init(container: Any, label: String, onAdjust: @escaping (CGFloat) -> Void) {
        self.onAdjust = onAdjust
        super.init(accessibilityContainer: container)
        accessibilityLabel = label
        accessibilityTraits = .adjustable
        accessibilityHint = "Swipe up or down to adjust the crop area."
    }
    override func accessibilityIncrement() { onAdjust(1) }
    override func accessibilityDecrement() { onAdjust(-1) }
}

/// Overlay that dims/blurs outside the crop box, draws the shaped border, grid,
/// and corner marks — and routes touches: handle areas resize the box, the
/// interior passes through to the scroll view for pan/zoom.
final class CropOverlayView: UIView {
    var cropBox: CGRect = .zero { didSet { setNeedsDisplay(); maskShapeLayer.frame = bounds; updateBlurMask() } }
    var shape: CropShape = .rectangle { didSet { setNeedsDisplay(); updateBlurMask() } }
    var showsGrid = true { didSet { setNeedsDisplay() } }
    var maskColor: UIColor = UIColor.black.withAlphaComponent(0.55) { didSet { setNeedsDisplay() } }
    var hotArea: CGFloat = 44
    /// The handle currently being dragged — highlighted while active.
    var activeEdge: CropEdge = .none { didSet { setNeedsDisplay() } }
    /// While interacting, show a denser grid and (for the blur mask) cross-fade to
    /// a plain dim so the image stays readable during the gesture.
    var isInteracting = false {
        didSet {
            guard isInteracting != oldValue else { return }
            setNeedsDisplay()
            guard let blurView else { return }
            UIView.animate(withDuration: 0.2) { blurView.alpha = self.isInteracting ? 0 : 1 }
        }
    }
    /// VoiceOver handle adjustment: `(edge, +1 grow / -1 shrink)`.
    var onHandleAdjust: ((CropEdge, CGFloat) -> Void)?

    private let blurView: UIVisualEffectView?
    private let maskShapeLayer = CAShapeLayer()

    init(maskStyle: CropMaskStyle) {
        if case let .blur(style) = maskStyle {
            blurView = UIVisualEffectView(effect: UIBlurEffect(style: style))
        } else {
            blurView = nil
        }
        super.init(frame: .zero)
        backgroundColor = .clear
        contentMode = .redraw
        if let blurView {
            blurView.isUserInteractionEnabled = false
            addSubview(blurView)
            blurView.layer.mask = maskShapeLayer
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView?.frame = bounds
        maskShapeLayer.frame = bounds
        updateBlurMask()
    }

    private func shapePath(in rect: CGRect) -> UIBezierPath { shape.bezierPath(in: rect) }

    /// For the blur variant, punch the crop shape out of the blur layer.
    private func updateBlurMask() {
        guard blurView != nil else { return }
        let path = UIBezierPath(rect: bounds)
        path.append(shapePath(in: cropBox))
        path.usesEvenOddFillRule = true
        maskShapeLayer.path = path.cgPath
        maskShapeLayer.fillRule = .evenOdd
    }

    override func draw(_ rect: CGRect) {
        // Blur mask cross-fades out while interacting; draw the dim then.
        if blurView == nil || isInteracting {
            maskColor.setFill()
            let mask = UIBezierPath(rect: bounds)
            mask.append(shapePath(in: cropBox))
            mask.usesEvenOddFillRule = true
            mask.fill()
        }

        UIColor.white.setStroke()
        let border = shapePath(in: cropBox)
        border.lineWidth = 1
        border.stroke()

        let b = cropBox
        // Highlight the edge(s) being dragged.
        if activeEdge.isActive {
            let hi = UIBezierPath()
            func top() { hi.move(to: CGPoint(x: b.minX, y: b.minY)); hi.addLine(to: CGPoint(x: b.maxX, y: b.minY)) }
            func bottom() { hi.move(to: CGPoint(x: b.minX, y: b.maxY)); hi.addLine(to: CGPoint(x: b.maxX, y: b.maxY)) }
            func left() { hi.move(to: CGPoint(x: b.minX, y: b.minY)); hi.addLine(to: CGPoint(x: b.minX, y: b.maxY)) }
            func right() { hi.move(to: CGPoint(x: b.maxX, y: b.minY)); hi.addLine(to: CGPoint(x: b.maxX, y: b.maxY)) }
            switch activeEdge {
            case .top: top()
            case .bottom: bottom()
            case .left: left()
            case .right: right()
            case .topLeft: top(); left()
            case .topRight: top(); right()
            case .bottomLeft: bottom(); left()
            case .bottomRight: bottom(); right()
            case .none: break
            }
            UIColor.systemYellow.setStroke(); hi.lineWidth = 2; hi.stroke()
        }

        // Corner marks
        let corner: CGFloat = 18
        UIColor.white.setStroke()
        let marks = UIBezierPath()
        func L(_ a: CGPoint, _ c: CGPoint) { marks.move(to: a); marks.addLine(to: c) }
        L(CGPoint(x: b.minX, y: b.minY + corner), CGPoint(x: b.minX, y: b.minY)); L(CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.minX + corner, y: b.minY))
        L(CGPoint(x: b.maxX - corner, y: b.minY), CGPoint(x: b.maxX, y: b.minY)); L(CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.maxX, y: b.minY + corner))
        L(CGPoint(x: b.minX, y: b.maxY - corner), CGPoint(x: b.minX, y: b.maxY)); L(CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.minX + corner, y: b.maxY))
        L(CGPoint(x: b.maxX - corner, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)); L(CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY - corner))
        marks.lineWidth = 3
        marks.stroke()

        // Rule-of-thirds normally; a denser grid while interacting (easier alignment).
        guard showsGrid || isInteracting else { return }
        let divisions = isInteracting ? 4 : 3
        let grid = UIBezierPath()
        for i in 1..<divisions {
            let x = b.minX + b.width * CGFloat(i) / CGFloat(divisions)
            grid.move(to: CGPoint(x: x, y: b.minY)); grid.addLine(to: CGPoint(x: x, y: b.maxY))
            let y = b.minY + b.height * CGFloat(i) / CGFloat(divisions)
            grid.move(to: CGPoint(x: b.minX, y: y)); grid.addLine(to: CGPoint(x: b.maxX, y: y))
        }
        UIColor.white.withAlphaComponent(0.5).setStroke()
        grid.lineWidth = 0.5
        grid.stroke()
    }

    /// Which edge/corner (if any) the point hits — for starting a resize.
    func edge(at point: CGPoint) -> CropEdge {
        let h = hotArea
        let b = cropBox
        let nearL = abs(point.x - b.minX) <= h, nearR = abs(point.x - b.maxX) <= h
        let nearT = abs(point.y - b.minY) <= h, nearB = abs(point.y - b.maxY) <= h
        let inX = point.x >= b.minX - h && point.x <= b.maxX + h
        let inY = point.y >= b.minY - h && point.y <= b.maxY + h
        guard inX, inY else { return .none }
        if nearL && nearT { return .topLeft }
        if nearR && nearT { return .topRight }
        if nearL && nearB { return .bottomLeft }
        if nearR && nearB { return .bottomRight }
        if nearT { return .top }; if nearB { return .bottom }
        if nearL { return .left }; if nearR { return .right }
        return .none
    }

    // Pass interior touches through to the scroll view; keep handle-area touches.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        edge(at: point).isActive ? self : nil
    }

    // MARK: - Accessibility

    override var accessibilityElements: [Any]? {
        get { handleAccessibilityElements() }
        set {}
    }

    private func handleAccessibilityElements() -> [Any] {
        CropEdge.handles.map { edge in
            let element = CropHandleAccessibilityElement(container: self, label: edge.accessibilityLabel) { [weak self] direction in
                self?.onHandleAdjust?(edge, direction)
            }
            let point = handlePoint(edge)
            element.accessibilityFrameInContainerSpace = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            return element
        }
    }

    private func handlePoint(_ edge: CropEdge) -> CGPoint {
        let b = cropBox
        switch edge {
        case .topLeft: return CGPoint(x: b.minX, y: b.minY)
        case .top: return CGPoint(x: b.midX, y: b.minY)
        case .topRight: return CGPoint(x: b.maxX, y: b.minY)
        case .left: return CGPoint(x: b.minX, y: b.midY)
        case .right: return CGPoint(x: b.maxX, y: b.midY)
        case .bottomLeft: return CGPoint(x: b.minX, y: b.maxY)
        case .bottom: return CGPoint(x: b.midX, y: b.maxY)
        case .bottomRight: return CGPoint(x: b.maxX, y: b.maxY)
        case .none: return .zero
        }
    }
}

/// Interactive image cropper: pan + pinch-zoom the
/// image, **drag the crop-box handles to resize** (free or aspect-locked), with
/// shapes (rect / ellipse / rounded), dim or blur mask, grid, 90° rotate, flip,
/// reset, fine rotation, and EXIF-correct output via the ``ImageCropper`` engine.
public final class CropperView: UIView, UIScrollViewDelegate {

    public private(set) var configuration: CropConfiguration
    public var onChange: (() -> Void)?

    private var workingImage: UIImage
    private var displayImage: UIImage
    /// A downscaled copy of ``workingImage`` used to render the live preview so
    /// dragging sliders stays smooth; the full-resolution render only happens on
    /// export. Rebuilt whenever ``workingImage`` changes.
    private var previewBase: UIImage
    /// Longest edge (in pixels) of the interactive preview.
    private let maxPreviewDimension: CGFloat = 1024

    /// Live color adjustments applied to the preview and the output.
    public var adjustments: ImageAdjustments = .none { didSet { refreshDisplay() } }
    /// Preset photo filter applied to the preview and the output.
    public var colorFilter: ColorFilter = .none { didSet { refreshDisplay() } }
    /// Filter strength in `0…1`.
    public var filterIntensity: CGFloat = 1 { didSet { refreshDisplay() } }
    /// Instagram-style film preset applied to the preview and the output (`nil` = none).
    public var filmPreset: FilmPreset? { didSet { refreshDisplay() } }
    /// Film preset strength in `0…1`.
    public var filmIntensity: CGFloat = 1 { didSet { refreshDisplay() } }

    private var _rotationAngle: CGFloat = 0
    /// Fine-rotation angle in radians, clamped to `±configuration.rotationLimit`.
    /// Setting it re-scales the image so it always covers the crop box (no empty
    /// corners) and keeps the covered region centered.
    public var rotationAngle: CGFloat {
        get { _rotationAngle }
        set {
            let limit = max(0, configuration.rotationLimit)
            _rotationAngle = min(max(newValue, -limit), limit)
            rotationContainer.transform = CGAffineTransform(rotationAngle: _rotationAngle)
            updateRotationCoverage(recenter: true)
            onChange?()
        }
    }

    private let rotationContainer = UIView()
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let overlay: CropOverlayView
    private var cropBox: CGRect = .zero
    private var didInitialLayout = false

    // Resize scratch
    private var activeEdge: CropEdge = .none
    private var startBox: CGRect = .zero
    private let haptic = UISelectionFeedbackGenerator()
    /// True while the scroll view is being adjusted programmatically (coverage /
    /// layout), so the scroll delegates don't fire `onChange` mid-layout.
    private var isProgrammaticScroll = false

    public init(image: UIImage, configuration: CropConfiguration = .init()) {
        let normalized = ImageCropper.normalizedUp(image)
        self.workingImage = normalized
        self.previewBase = CropperView.downscaled(normalized, maxDimension: 1024)
        self.displayImage = self.previewBase
        self.configuration = configuration
        self.overlay = CropOverlayView(maskStyle: configuration.maskStyle)
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .black

        rotationContainer.addSubview(scrollView)
        addSubview(rotationContainer)
        addSubview(overlay)

        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.maximumZoomScale = configuration.maxZoom
        scrollView.clipsToBounds = false
        imageView.image = displayImage
        scrollView.addSubview(imageView)

        overlay.shape = configuration.shape
        overlay.showsGrid = configuration.showsGrid
        overlay.maskColor = configuration.maskColor
        overlay.hotArea = configuration.disableCropBoxDeformation ? 0 : configuration.handleHotArea
        overlay.onHandleAdjust = { [weak self] edge, direction in
            self?.adjustBox(edge: edge, grow: 20 * direction)
        }
        overlay.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleResize)))
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Capture the image frame before relayout so we can keep the crop box
        // proportional if the available area changed (e.g. the adjust panel
        // toggling resizes the cropper).
        let oldImageFrame = imageFrameInView
        overlay.frame = bounds
        // Setting a frame while a rotation transform is active is undefined and
        // shifts the view off-center — lay it out untransformed, then re-rotate.
        rotationContainer.transform = .identity
        rotationContainer.frame = bounds
        rotationContainer.transform = CGAffineTransform(rotationAngle: rotationAngle)

        let area = bounds.insetBy(dx: configuration.padding, dy: configuration.padding)
        scrollView.frame = area

        let fit = fitSize(for: area.size, imageSize: workingImage.size)
        imageView.frame = CGRect(origin: .zero, size: fit)
        scrollView.contentSize = fit
        scrollView.minimumZoomScale = 1
        if !didInitialLayout { scrollView.zoomScale = 1 }
        centerContent()

        if !didInitialLayout {
            cropBox = defaultCropBox()
            overlay.cropBox = cropBox
            didInitialLayout = true
        } else {
            let newImageFrame = imageFrameInView
            // Re-map the crop box proportionally when the image frame changed, so
            // switching tools / toggling panels doesn't shift or resize the selection.
            if oldImageFrame.width > 1, oldImageFrame.height > 1,
               newImageFrame.width > 1, newImageFrame.height > 1,
               newImageFrame != oldImageFrame {
                let nx = (cropBox.minX - oldImageFrame.minX) / oldImageFrame.width
                let ny = (cropBox.minY - oldImageFrame.minY) / oldImageFrame.height
                let nw = cropBox.width / oldImageFrame.width
                let nh = cropBox.height / oldImageFrame.height
                cropBox = CGRect(x: newImageFrame.minX + nx * newImageFrame.width,
                                 y: newImageFrame.minY + ny * newImageFrame.height,
                                 width: nw * newImageFrame.width,
                                 height: nh * newImageFrame.height)
                overlay.cropBox = cropBox
            }
        }
        updateRotationCoverage(recenter: false)
    }

    private func fitSize(for area: CGSize, imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return area }
        let scale = min(area.width / imageSize.width, area.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func centerContent() {
        let content = scrollView.contentSize
        let box = scrollView.bounds.size
        scrollView.contentInset = UIEdgeInsets(
            top: max(0, (box.height - content.height) / 2),
            left: max(0, (box.width - content.width) / 2),
            bottom: 0, right: 0)
    }

    /// The image's on-screen frame, in this view's coordinates.
    private var imageFrameInView: CGRect { convert(imageView.bounds, from: imageView) }

    // MARK: - Rotation coverage

    /// Half-extents (in points) of the crop box after it is rotated by `angle`
    /// into the image's own coordinate space — the axis-aligned box the image
    /// must contain so no empty corners show through.
    private func rotatedBoxHalfExtents(_ angle: CGFloat) -> CGSize {
        let c = abs(cos(angle)), s = abs(sin(angle))
        return CGSize(width: (cropBox.width * c + cropBox.height * s) / 2,
                      height: (cropBox.width * s + cropBox.height * c) / 2)
    }

    /// Raise the minimum zoom so the (rotated) image always covers the crop box,
    /// bump the current zoom to meet it, optionally re-center on the crop box, and
    /// clamp the offset so panning can't expose a corner. No-op at angle 0 with a
    /// box no larger than the fitted image.
    private func updateRotationCoverage(recenter: Bool) {
        let fit = fitSize(for: scrollView.frame.size, imageSize: workingImage.size)
        guard fit.width > 1, fit.height > 1, cropBox.width > 1, cropBox.height > 1 else { return }
        let h = rotatedBoxHalfExtents(_rotationAngle)
        let coverage = max(1, max(2 * h.width / fit.width, 2 * h.height / fit.height))
        // These programmatic scroll/zoom mutations fire the scroll delegates, but
        // they must NOT cascade into `onChange` — this runs during `layoutSubviews`,
        // and notifying observers there mutates SwiftUI state mid-update.
        isProgrammaticScroll = true
        scrollView.minimumZoomScale = coverage
        if scrollView.zoomScale < coverage { scrollView.zoomScale = coverage }
        if recenter { centerContentOnBox() }
        clampOffsetForRotation()
        isProgrammaticScroll = false
    }

    /// Center the zoomed content under the (centered) crop box.
    private func centerContentOnBox() {
        let content = scrollView.contentSize
        let area = scrollView.bounds.size
        scrollView.contentOffset = CGPoint(x: max(0, (content.width - area.width) / 2),
                                           y: max(0, (content.height - area.height) / 2))
    }

    /// Keep the rotated crop box fully inside the image while panning. Assumes the
    /// box is centered in the scroll area (the resting state the editor maintains).
    private func clampOffsetForRotation() {
        guard _rotationAngle != 0 else { return }
        let content = scrollView.contentSize
        let area = scrollView.bounds.size
        let h = rotatedBoxHalfExtents(_rotationAngle)
        let loX = h.width - area.width / 2, hiX = content.width - h.width - area.width / 2
        let loY = h.height - area.height / 2, hiY = content.height - h.height - area.height / 2
        var o = scrollView.contentOffset
        o.x = min(max(o.x, min(loX, hiX)), max(loX, hiX))
        o.y = min(max(o.y, min(loY, hiY)), max(loY, hiY))
        if o != scrollView.contentOffset { scrollView.contentOffset = o }
    }

    private func defaultCropBox() -> CGRect {
        let image = imageFrameInView
        guard let ratio = configuration.aspectRatio.value(for: workingImage.size) else { return image }
        var size = image.size
        if image.width / image.height > ratio { size.width = image.height * ratio }
        else { size.height = image.width / ratio }
        return CGRect(x: image.midX - size.width / 2, y: image.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    // MARK: - Scroll view

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        guard !isProgrammaticScroll else { return }
        clampOffsetForRotation(); onChange?()
    }
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isProgrammaticScroll else { return }
        clampOffsetForRotation()
    }
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { recordUndo(); overlay.isInteracting = true }
    public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { recordUndo(); overlay.isInteracting = true }
    public func scrollViewDidEndDragging(_ s: UIScrollView, willDecelerate: Bool) {
        if !willDecelerate { overlay.isInteracting = false }
        onChange?()
    }
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { overlay.isInteracting = false }
    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { overlay.isInteracting = false }

    // MARK: - Resize handles

    @objc private func handleResize(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: overlay)
        switch g.state {
        case .began:
            guard !configuration.disableCropBoxDeformation else { return }
            activeEdge = overlay.edge(at: p)
            guard activeEdge.isActive else { return }
            recordUndo()
            startBox = cropBox
            overlay.activeEdge = activeEdge
            overlay.isInteracting = true
            haptic.prepare()
        case .changed:
            guard activeEdge.isActive else { return }
            cropBox = resizedBox(startBox, edge: activeEdge, translation: g.translation(in: overlay))
            overlay.cropBox = cropBox
            onChange?()
        case .ended, .cancelled:
            guard activeEdge.isActive else { return }
            activeEdge = .none
            overlay.activeEdge = .none
            overlay.isInteracting = false
            haptic.selectionChanged()
            if configuration.growsBackAfterResize { animateBoxToFill() }
            updateRotationCoverage(recenter: false)
        default: break
        }
    }

    /// Animate the crop box back to fill the available area (keeping its aspect),
    /// zooming the image so the cropped region is preserved.
    private func animateBoxToFill() {
        let area = scrollView.frame
        guard cropBox.width > 1, cropBox.height > 1 else { return }
        let aspect = cropBox.width / cropBox.height
        var target = area
        if area.width / area.height > aspect { target.size.width = area.height * aspect }
        else { target.size.height = area.width / aspect }
        target.origin = CGPoint(x: area.midX - target.width / 2, y: area.midY - target.height / 2)

        let factor = min(target.width / cropBox.width, target.height / cropBox.height)
        guard factor > 1.01 else { return }

        let zoom = scrollView.zoomScale
        let boxCenterInScroll = CGPoint(x: cropBox.midX - area.minX, y: cropBox.midY - area.minY)
        let imagePoint = CGPoint(x: (scrollView.contentOffset.x + boxCenterInScroll.x) / zoom,
                                 y: (scrollView.contentOffset.y + boxCenterInScroll.y) / zoom)
        let newZoom = min(zoom * factor, scrollView.maximumZoomScale)
        let targetBoxCenterInScroll = CGPoint(x: target.midX - area.minX, y: target.midY - area.minY)

        UIView.animate(withDuration: 0.3) {
            self.scrollView.zoomScale = newZoom
            self.scrollView.contentOffset = CGPoint(x: imagePoint.x * newZoom - targetBoxCenterInScroll.x,
                                                    y: imagePoint.y * newZoom - targetBoxCenterInScroll.y)
            self.cropBox = target
            self.overlay.cropBox = target
        }
    }

    private func resizedBox(_ start: CGRect, edge: CropEdge, translation t: CGPoint) -> CGRect {
        var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
        switch edge {
        case .topLeft: minX += t.x; minY += t.y
        case .top: minY += t.y
        case .topRight: maxX += t.x; minY += t.y
        case .left: minX += t.x
        case .right: maxX += t.x
        case .bottomLeft: minX += t.x; maxY += t.y
        case .bottom: maxY += t.y
        case .bottomRight: maxX += t.x; maxY += t.y
        case .none: break
        }
        let bounds = imageFrameInView.intersection(scrollView.frame)
        minX = max(minX, bounds.minX); minY = max(minY, bounds.minY)
        maxX = min(maxX, bounds.maxX); maxY = min(maxY, bounds.maxY)
        let m = configuration.minimumBoxSize
        if maxX - minX < m { if edge == .left || edge == .topLeft || edge == .bottomLeft { minX = maxX - m } else { maxX = minX + m } }
        if maxY - minY < m { if edge == .top || edge == .topLeft || edge == .topRight { minY = maxY - m } else { maxY = minY + m } }
        var box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // Aspect lock: derive height from width, anchored at the box center-ish.
        if let ratio = configuration.aspectRatio.value(for: workingImage.size) {
            let h = box.width / ratio
            switch edge {
            case .top, .topLeft, .topRight: box.origin.y = box.maxY - h
            default: break
            }
            box.size.height = h
            box = box.intersection(bounds)
        }
        return box
    }

    // MARK: - Actions

    public func setAspectRatio(_ ratio: CropAspectRatio) {
        recordUndo()
        configuration.aspectRatio = ratio
        cropBox = defaultCropBox()
        overlay.cropBox = cropBox
        onChange?()
    }

    public func setShape(_ shape: CropShape) {
        recordUndo()
        configuration.shape = shape
        overlay.shape = shape
        onChange?()
    }

    /// Rotate the image 90° (exact re-orientation of the working image).
    public func rotate90(clockwise: Bool = true) {
        recordUndo()
        guard let rotated = ImageCropper.rotated90(workingImage, quarterTurns: clockwise ? 1 : -1) else { return }
        workingImage = rotated
        rebuildPreviewBase()
        didInitialLayout = false
        refreshDisplay()
        setNeedsLayout(); layoutIfNeeded()
    }

    /// Rotate the image 90° counter-clockwise.
    public func rotate90CounterClockwise() { rotate90(clockwise: false) }

    /// Swap the crop box between portrait and landscape without rotating the image.
    public func alterCropBox90() {
        recordUndo()
        let center = CGPoint(x: cropBox.midX, y: cropBox.midY)
        let bounds = imageFrameInView.intersection(scrollView.frame)
        let box = CGRect(x: center.x - cropBox.height / 2, y: center.y - cropBox.width / 2,
                         width: cropBox.height, height: cropBox.width).intersection(bounds)
        guard box.width > configuration.minimumBoxSize, box.height > configuration.minimumBoxSize else { return }
        if case let .ratio(w, h) = configuration.aspectRatio { configuration.aspectRatio = .ratio(h, w) }
        cropBox = box
        overlay.cropBox = box
        updateRotationCoverage(recenter: false)
        onChange?()
    }

    /// Single-step resize of one handle (used by VoiceOver). `grow > 0` enlarges.
    private func adjustBox(edge: CropEdge, grow: CGFloat) {
        recordUndo()
        var translation = CGPoint.zero
        switch edge {
        case .left, .topLeft, .bottomLeft: translation.x = -grow
        case .right, .topRight, .bottomRight: translation.x = grow
        default: break
        }
        switch edge {
        case .top, .topLeft, .topRight: translation.y = -grow
        case .bottom, .bottomLeft, .bottomRight: translation.y = grow
        default: break
        }
        cropBox = resizedBox(cropBox, edge: edge, translation: translation)
        overlay.cropBox = cropBox
        updateRotationCoverage(recenter: false)
        onChange?()
    }

    /// Flip the working image (baked in, so the crop stays exact).
    public func flip(horizontally: Bool = true) {
        recordUndo()
        guard let out = ImageCropper.flipped(workingImage, horizontally: horizontally, vertically: !horizontally) else { return }
        workingImage = out
        rebuildPreviewBase()
        refreshDisplay()
    }

    /// When true, property `didSet`s skip rendering so a batch update (undo/redo
    /// restore) renders once instead of once per changed property.
    private var isBatchUpdating = false

    private func refreshDisplay() {
        guard !isBatchUpdating else { return }
        // Render the small preview base — fast enough to keep slider drags smooth.
        displayImage = ImageCropper.process(previewBase, adjustments: adjustments,
                                            filter: colorFilter, filterIntensity: filterIntensity,
                                            film: filmPreset, filmIntensity: filmIntensity)
        imageView.image = displayImage
        onChange?()
    }

    /// Full-resolution processed image (adjustments + filter + film), used only on export.
    private func processedFullResolution() -> UIImage {
        ImageCropper.process(workingImage, adjustments: adjustments,
                             filter: colorFilter, filterIntensity: filterIntensity,
                             film: filmPreset, filmIntensity: filmIntensity)
    }

    private func rebuildPreviewBase() {
        previewBase = CropperView.downscaled(workingImage, maxDimension: maxPreviewDimension)
    }

    /// Downscale so the longest edge is at most `maxDimension` px (never upscales).
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width))
        let pixelHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height))
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Undo / redo

    public let viewModel = CropViewModel()
    public var canUndo: Bool { viewModel.canUndo }
    public var canRedo: Bool { viewModel.canRedo }

    /// The full editor state as a UI-independent document.
    public func currentDocument() -> CropDocument {
        CropDocument(workingImage: workingImage, crop: cropState(),
                     adjustments: adjustments, colorFilter: colorFilter,
                     filterIntensity: filterIntensity, filmPreset: filmPreset,
                     filmIntensity: filmIntensity,
                     aspectRatio: configuration.aspectRatio, shape: configuration.shape)
    }

    /// Record an undo point immediately before a mutation.
    public func recordUndo() {
        viewModel.record(currentDocument())
        onChange?()
    }

    public func undo() {
        guard let doc = viewModel.undo(current: currentDocument()) else { return }
        apply(document: doc)
    }

    public func redo() {
        guard let doc = viewModel.redo(current: currentDocument()) else { return }
        apply(document: doc)
    }

    private func apply(document doc: CropDocument) {
        isBatchUpdating = true
        // Only re-downscale when the base image actually changed (rotate/flip/crop);
        // undoing an adjustment/filter/film change leaves workingImage identical, so
        // rebuilding the preview base every time was the bulk of undo/redo latency.
        if doc.workingImage !== workingImage {
            workingImage = doc.workingImage
            rebuildPreviewBase()
        }
        adjustments = doc.adjustments
        colorFilter = doc.colorFilter
        filterIntensity = doc.filterIntensity
        filmPreset = doc.filmPreset
        filmIntensity = doc.filmIntensity
        configuration.aspectRatio = doc.aspectRatio
        configuration.shape = doc.shape
        overlay.shape = doc.shape
        didInitialLayout = true
        isBatchUpdating = false
        refreshDisplay()
        setNeedsLayout(); layoutIfNeeded()
        restore(doc.crop)
        onChange?()
    }

    // Undo-aware setters (used by the SwiftUI controller / editor).
    public func setColorFilter(_ filter: ColorFilter) { recordUndo(); colorFilter = filter }
    public func setFilmPreset(_ preset: FilmPreset?) { recordUndo(); filmPreset = preset }
    public func setFilmIntensity(_ value: CGFloat) { filmIntensity = value }
    /// Call once when a slider drag begins so the whole drag is one undo step.
    public func beginAdjustment() { recordUndo() }
    public func setFilterIntensity(_ value: CGFloat) { filterIntensity = value }
    public func setAdjustments(_ value: ImageAdjustments) { adjustments = value }

    public func reset() {
        recordUndo()
        rotationAngle = 0
        rotationContainer.transform = .identity
        scrollView.zoomScale = 1
        adjustments = .none
        colorFilter = .none
        filterIntensity = 1
        didInitialLayout = false
        setNeedsLayout(); layoutIfNeeded()
        refreshDisplay()
    }

    // MARK: - Auto detect / straighten

    /// Detect the horizon and rotate the image so it's level (a no-op if none is
    /// found). Vision runs off-main so the UI stays responsive.
    public func autoStraighten() async {
        let image = workingImage
        let angle = await Task.detached(priority: .userInitiated) {
            image.cgImage.flatMap { HorizonDetector.levelingAngle(in: $0) }
        }.value
        guard let angle, abs(angle) > 0.001 else { return }
        recordUndo()
        rotationAngle = angle   // clamped + coverage handled by the setter
    }

    /// Detect a document/rectangle and snap the crop box to it (iOS 26+). Resets
    /// zoom and rotation first so the detected region maps predictably.
    @available(iOS 26, *)
    public func autoDetectCropBox() async {
        let image = workingImage
        guard let cg = image.cgImage,
              let quad = try? await DocumentEdgeDetector().detectQuad(in: cg) else { return }
        recordUndo()
        _rotationAngle = 0
        rotationContainer.transform = .identity
        scrollView.zoomScale = 1
        didInitialLayout = false
        setNeedsLayout(); layoutIfNeeded()
        setCropBox(fromNormalizedQuad: quad)
    }

    /// Map a Vision quad (normalized, bottom-left origin) to the crop box.
    private func setCropBox(fromNormalizedQuad quad: DocumentQuad) {
        let xs = [quad.topLeft.x, quad.topRight.x, quad.bottomLeft.x, quad.bottomRight.x]
        let ys = [quad.topLeft.y, quad.topRight.y, quad.bottomLeft.y, quad.bottomRight.y]
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return }
        // Vision's origin is bottom-left; flip Y to the view's top-left space.
        let topN = 1 - maxY, bottomN = 1 - minY
        let img = imageFrameInView
        let box = CGRect(x: img.minX + minX * img.width,
                         y: img.minY + topN * img.height,
                         width: (maxX - minX) * img.width,
                         height: (bottomN - topN) * img.height)
            .intersection(img.intersection(scrollView.frame))
        guard box.width > configuration.minimumBoxSize, box.height > configuration.minimumBoxSize else { return }
        configuration.aspectRatio = .free   // a detected document has an arbitrary aspect
        cropBox = box
        overlay.cropBox = box
        updateRotationCoverage(recenter: false)
        onChange?()
    }

    // MARK: - Output

    /// Crop inputs gathered from the (main-thread) view state — so the actual
    /// render can run either inline or off-main with identical parameters.
    private func cropParameters() -> (source: UIImage, rectPx: CGRect?, info: CropInfo?)? {
        // Render at full resolution here (the live preview uses a downscaled base).
        let source = processedFullResolution()
        if rotationAngle == 0 {
            let image = imageFrameInView
            guard image.width > 0 else { return nil }
            let pxPerPoint = CGFloat(source.cgImage?.width ?? 1) / image.width
            let rectPx = CGRect(
                x: (cropBox.minX - image.minX) * pxPerPoint,
                y: (cropBox.minY - image.minY) * pxPerPoint,
                width: cropBox.width * pxPerPoint,
                height: cropBox.height * pxPerPoint)
            return (source, rectPx, nil)
        } else {
            let zoom = scrollView.zoomScale
            let fit = CGSize(width: scrollView.contentSize.width / zoom, height: scrollView.contentSize.height / zoom)
            let info = CropInfo(rotation: rotationAngle, scale: zoom, cropSize: cropBox.size, imageViewSize: fit)
            return (source, nil, info)
        }
    }

    private nonisolated static func render(_ p: (source: UIImage, rectPx: CGRect?, info: CropInfo?), shape: CropShape) -> UIImage? {
        let base = p.rectPx.flatMap { ImageCropper.crop(p.source, to: $0) }
            ?? p.info.flatMap { ImageCropper.crop(p.source, by: $0) }
        guard let base else { return nil }
        return ImageCropper.masked(base, shape: shape)
    }

    /// The shape used for the exported image — rectangular when ``CropConfiguration/maskOnly``
    /// is set (the shaped mask is on-screen only).
    private var outputShape: CropShape { configuration.maskOnly ? .rectangle : configuration.shape }

    /// Synchronous crop (fine for small images / immediate use).
    public func croppedImage() -> UIImage? {
        guard let p = cropParameters() else { return nil }
        return Self.render(p, shape: outputShape)
    }

    /// Off-main crop — renders on a background task to keep the UI responsive
    /// for large images.
    public func croppedImageAsync() async -> UIImage? {
        guard let p = cropParameters() else { return nil }
        let shape = outputShape
        return await Task.detached(priority: .userInitiated) {
            CropperView.render(p, shape: shape)
        }.value
    }

    /// Apply the current crop (geometry + rotation + shape + color) to another
    /// image that shares the source's pixel dimensions — e.g. to batch-apply one
    /// set of edits across aligned frames.
    public func process(_ image: UIImage) -> UIImage? {
        guard let p = cropParameters() else { return nil }
        let processed = ImageCropper.process(image, adjustments: adjustments, filter: colorFilter,
                                             filterIntensity: filterIntensity, film: filmPreset,
                                             filmIntensity: filmIntensity)
        return Self.render((source: processed, rectPx: p.rectPx, info: p.info), shape: outputShape)
    }

    // MARK: - Save / restore (re-open a previous crop). `CropState` is top-level.

    public func cropState() -> CropState {
        let img = imageFrameInView
        let box = img.width > 0 && img.height > 0
            ? CGRect(x: (cropBox.minX - img.minX) / img.width,
                     y: (cropBox.minY - img.minY) / img.height,
                     width: cropBox.width / img.width,
                     height: cropBox.height / img.height)
            : CGRect(x: 0, y: 0, width: 1, height: 1)
        let content = scrollView.contentSize
        let offset = CGPoint(x: content.width > 0 ? scrollView.contentOffset.x / content.width : 0,
                             y: content.height > 0 ? scrollView.contentOffset.y / content.height : 0)
        return CropState(normalizedBox: box, zoomScale: scrollView.zoomScale,
                         normalizedOffset: offset, rotationAngle: rotationAngle)
    }

    /// Restore a previously saved ``CropState``.
    public func restore(_ state: CropState) {
        setNeedsLayout(); layoutIfNeeded()
        scrollView.zoomScale = min(max(state.zoomScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let content = scrollView.contentSize
        scrollView.contentOffset = CGPoint(x: state.normalizedOffset.x * content.width,
                                           y: state.normalizedOffset.y * content.height)
        rotationAngle = state.rotationAngle
        let img = imageFrameInView
        cropBox = CGRect(x: img.minX + state.normalizedBox.minX * img.width,
                         y: img.minY + state.normalizedBox.minY * img.height,
                         width: state.normalizedBox.width * img.width,
                         height: state.normalizedBox.height * img.height)
        overlay.cropBox = cropBox
        onChange?()
    }
}

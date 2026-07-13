//
//  CropperView.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

enum CropEdge {
    case none, topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    var isActive: Bool { self != .none }
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

    private func shapePath(in rect: CGRect) -> UIBezierPath {
        switch shape {
        case .rectangle: return UIBezierPath(rect: rect)
        case .ellipse: return UIBezierPath(ovalIn: rect)
        case .roundedRect(let r): return UIBezierPath(roundedRect: rect, cornerRadius: r)
        }
    }

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
        if blurView == nil {
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

        // Corner marks
        let corner: CGFloat = 18
        UIColor.white.setStroke()
        let marks = UIBezierPath()
        let b = cropBox
        func L(_ a: CGPoint, _ c: CGPoint) { marks.move(to: a); marks.addLine(to: c) }
        L(CGPoint(x: b.minX, y: b.minY + corner), CGPoint(x: b.minX, y: b.minY)); L(CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.minX + corner, y: b.minY))
        L(CGPoint(x: b.maxX - corner, y: b.minY), CGPoint(x: b.maxX, y: b.minY)); L(CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.maxX, y: b.minY + corner))
        L(CGPoint(x: b.minX, y: b.maxY - corner), CGPoint(x: b.minX, y: b.maxY)); L(CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.minX + corner, y: b.maxY))
        L(CGPoint(x: b.maxX - corner, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)); L(CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY - corner))
        marks.lineWidth = 3
        marks.stroke()

        guard showsGrid else { return }
        let grid = UIBezierPath()
        for i in 1...2 {
            let x = b.minX + b.width * CGFloat(i) / 3
            grid.move(to: CGPoint(x: x, y: b.minY)); grid.addLine(to: CGPoint(x: x, y: b.maxY))
            let y = b.minY + b.height * CGFloat(i) / 3
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
}

/// Interactive image cropper (TOCropViewController-style): pan + pinch-zoom the
/// image, **drag the crop-box handles to resize** (free or aspect-locked), with
/// shapes (rect / ellipse / rounded), dim or blur mask, grid, 90° rotate, flip,
/// reset, fine rotation, and EXIF-correct output via the ``ImageCropper`` engine.
public final class CropperView: UIView, UIScrollViewDelegate {

    public private(set) var configuration: CropConfiguration
    public var onChange: (() -> Void)?

    private var workingImage: UIImage
    private var displayImage: UIImage

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

    public var rotationAngle: CGFloat = 0 {
        didSet { rotationContainer.transform = CGAffineTransform(rotationAngle: rotationAngle); onChange?() }
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

    public init(image: UIImage, configuration: CropConfiguration = .init()) {
        let normalized = ImageCropper.normalizedUp(image)
        self.workingImage = normalized
        self.displayImage = normalized
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
        overlay.hotArea = configuration.handleHotArea
        overlay.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleResize)))
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        overlay.frame = bounds
        rotationContainer.frame = bounds

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
        }
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
    public func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent(); onChange?() }
    public func scrollViewDidEndDragging(_ s: UIScrollView, willDecelerate: Bool) { onChange?() }
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { recordUndo() }
    public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { recordUndo() }

    // MARK: - Resize handles

    @objc private func handleResize(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: overlay)
        switch g.state {
        case .began:
            activeEdge = overlay.edge(at: p)
            if activeEdge.isActive { recordUndo() }
            startBox = cropBox
            haptic.prepare()
        case .changed:
            guard activeEdge.isActive else { return }
            cropBox = resizedBox(startBox, edge: activeEdge, translation: g.translation(in: overlay))
            overlay.cropBox = cropBox
            onChange?()
        case .ended, .cancelled:
            activeEdge = .none
            haptic.selectionChanged()
            if configuration.growsBackAfterResize { animateBoxToFill() }
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

    /// Rotate the image 90° clockwise (exact — re-orients the working image).
    public func rotate90() {
        recordUndo()
        guard let rotated = ImageCropper.rotated90(workingImage, quarterTurns: 1) else { return }
        workingImage = rotated
        didInitialLayout = false
        refreshDisplay()
        setNeedsLayout(); layoutIfNeeded()
    }

    /// Flip the working image (baked in, so the crop stays exact).
    public func flip(horizontally: Bool = true) {
        recordUndo()
        guard let out = ImageCropper.flipped(workingImage, horizontally: horizontally, vertically: !horizontally) else { return }
        workingImage = out
        refreshDisplay()
    }

    private func refreshDisplay() {
        displayImage = ImageCropper.process(workingImage, adjustments: adjustments,
                                            filter: colorFilter, filterIntensity: filterIntensity,
                                            film: filmPreset, filmIntensity: filmIntensity)
        imageView.image = displayImage
        onChange?()
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
        workingImage = doc.workingImage
        adjustments = doc.adjustments
        colorFilter = doc.colorFilter
        filterIntensity = doc.filterIntensity
        filmPreset = doc.filmPreset
        filmIntensity = doc.filmIntensity
        configuration.aspectRatio = doc.aspectRatio
        configuration.shape = doc.shape
        overlay.shape = doc.shape
        didInitialLayout = true
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

    // MARK: - Output

    /// Crop inputs gathered from the (main-thread) view state — so the actual
    /// render can run either inline or off-main with identical parameters.
    private func cropParameters() -> (source: UIImage, rectPx: CGRect?, info: CropInfo?)? {
        if rotationAngle == 0 {
            let image = imageFrameInView
            guard image.width > 0 else { return nil }
            let pxPerPoint = CGFloat(displayImage.cgImage?.width ?? 1) / image.width
            let rectPx = CGRect(
                x: (cropBox.minX - image.minX) * pxPerPoint,
                y: (cropBox.minY - image.minY) * pxPerPoint,
                width: cropBox.width * pxPerPoint,
                height: cropBox.height * pxPerPoint)
            return (displayImage, rectPx, nil)
        } else {
            let zoom = scrollView.zoomScale
            let fit = CGSize(width: scrollView.contentSize.width / zoom, height: scrollView.contentSize.height / zoom)
            let info = CropInfo(rotation: rotationAngle, scale: zoom, cropSize: cropBox.size, imageViewSize: fit)
            return (displayImage, nil, info)
        }
    }

    private nonisolated static func render(_ p: (source: UIImage, rectPx: CGRect?, info: CropInfo?), shape: CropShape) -> UIImage? {
        let base = p.rectPx.flatMap { ImageCropper.crop(p.source, to: $0) }
            ?? p.info.flatMap { ImageCropper.crop(p.source, by: $0) }
        guard let base else { return nil }
        return ImageCropper.masked(base, shape: shape)
    }

    /// Synchronous crop (fine for small images / immediate use).
    public func croppedImage() -> UIImage? {
        guard let p = cropParameters() else { return nil }
        return Self.render(p, shape: configuration.shape)
    }

    /// Off-main crop — renders on a background task to keep the UI responsive
    /// for large images.
    public func croppedImageAsync() async -> UIImage? {
        guard let p = cropParameters() else { return nil }
        let shape = configuration.shape
        return await Task.detached(priority: .userInitiated) {
            CropperView.render(p, shape: shape)
        }.value
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

//
//  StickerAnnotation.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import PDFKit
import UIKit

/// A `.stamp` annotation that draws an image with rotation and scale — the
/// primitive for burning a transformed overlay (e.g. a StickerKit item or a
/// flattened canvas) onto a PDF page. Rotation is negated internally because
/// PDF space is y-up while screen rotation is y-down.
public final class StickerAnnotation: PDFAnnotation {
    private let image: UIImage
    private let rotation: CGFloat
    private let contentScale: CGFloat

    /// - Parameters:
    ///   - bounds: annotation rect in **page** coordinates.
    ///   - rotation: on-screen rotation in radians (UIKit sense).
    ///   - scale: extra scale of the drawn image within `bounds` (1 = fill).
    public init(image: UIImage, bounds: CGRect, rotation: CGFloat = 0, scale: CGFloat = 1) {
        self.image = image
        self.rotation = rotation
        self.contentScale = scale
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("StickerAnnotation is not NSCoding-restorable") }

    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        UIGraphicsPushContext(context)
        context.saveGState()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -rotation)
        context.translateBy(x: -center.x, y: -center.y)

        let w = bounds.width * contentScale
        let h = bounds.height * contentScale
        let drawRect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        image.draw(in: drawRect)

        context.restoreGState()
        UIGraphicsPopContext()
    }
}

public extension PDFPage {

    /// Stamp `image` onto this page. `frame` is in `pdfView`'s coordinate space
    /// (e.g. an overlay view's frame) and is converted to page space for you.
    ///
    /// Pass the item's on-screen `rotation`/`scale` (from StickerKit's
    /// `TransformState`) to bake the transform in.
    @discardableResult
    func stamp(
        image: UIImage,
        frame: CGRect,
        in pdfView: PDFView,
        rotation: CGFloat = 0,
        scale: CGFloat = 1
    ) -> StickerAnnotation {
        let pageBounds = pdfView.convert(frame, to: self)
        let annotation = StickerAnnotation(image: image, bounds: pageBounds, rotation: rotation, scale: scale)
        addAnnotation(annotation)
        return annotation
    }

    /// Stamp `image` when you already have the rect in **page** coordinates.
    @discardableResult
    func stamp(
        image: UIImage,
        pageBounds: CGRect,
        rotation: CGFloat = 0,
        scale: CGFloat = 1
    ) -> StickerAnnotation {
        let annotation = StickerAnnotation(image: image, bounds: pageBounds, rotation: rotation, scale: scale)
        addAnnotation(annotation)
        return annotation
    }
}

//
//  PDFAnnotation+Factory.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import PDFKit
import UIKit

public extension PDFAnnotation {

    /// A free-text note. `bounds` are in PDF page space (origin bottom-left).
    static func freeText(
        _ text: String,
        bounds: CGRect,
        font: UIFont = .systemFont(ofSize: 14),
        color: UIColor = .label
    ) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        a.contents = text
        a.font = font
        a.fontColor = color
        a.color = .clear              // avoid the default yellow background box
        return a
    }

    /// A freehand ink annotation from one or more Bézier paths (page space).
    static func ink(
        paths: [UIBezierPath],
        bounds: CGRect,
        color: UIColor = .systemBlue,
        lineWidth: CGFloat = 4
    ) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        let border = PDFBorder()
        border.lineWidth = lineWidth
        a.border = border
        a.color = color
        paths.forEach { a.add($0) }
        return a
    }

    /// A highlight (or `.underline` / `.strikeOut`) markup over `bounds`.
    static func markup(
        _ subtype: PDFAnnotationSubtype = .highlight,
        bounds: CGRect,
        color: UIColor = .systemYellow
    ) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
        a.color = color
        return a
    }

    /// A tappable link over `bounds`.
    static func link(bounds: CGRect, url: URL) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
        a.url = url
        return a
    }

    /// An image stamp (PDFKit's `.stamp` doesn't render an image on its own).
    /// Backed by ``StickerAnnotation`` — the single image-drawing annotation.
    static func imageStamp(_ image: UIImage, bounds: CGRect) -> PDFAnnotation {
        StickerAnnotation(image: image, bounds: bounds)
    }
}

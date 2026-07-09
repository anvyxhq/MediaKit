//
//  Watermark.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import PDFKit
import UIKit

/// A configurable watermark (text or image) that can be drawn onto a page.
///
/// `scale` resizes it (to/nhỏ), `opacity` fades it, `rotation` tilts it, and
/// `layout` places it. Ready-made presets cover the common formats.
public struct Watermark {

    public enum Content {
        case text(String, font: UIFont, color: UIColor)
        case image(UIImage)
    }

    /// Where/how the watermark repeats across the page.
    public enum Layout: Equatable {
        case centered
        case tiled(spacing: CGSize)
        case topLeft, topRight, bottomLeft, bottomRight
    }

    public var content: Content
    public var layout: Layout
    public var opacity: CGFloat     // 0…1
    public var rotation: CGFloat    // radians
    public var scale: CGFloat       // size multiplier — làm to/nhỏ
    public var inset: CGFloat

    public init(content: Content, layout: Layout = .centered, opacity: CGFloat = 0.3,
                rotation: CGFloat = 0, scale: CGFloat = 1, inset: CGFloat = 24) {
        self.content = content; self.layout = layout; self.opacity = opacity
        self.rotation = rotation; self.scale = scale; self.inset = inset
    }

    // MARK: - Presets (định dạng sẵn)

    /// Big diagonal text across the page center (e.g. "CONFIDENTIAL").
    public static func diagonalText(_ text: String, font: UIFont = .boldSystemFont(ofSize: 48),
                                    color: UIColor = .gray, opacity: CGFloat = 0.28) -> Watermark {
        Watermark(content: .text(text, font: font, color: color), layout: .centered,
                  opacity: opacity, rotation: -.pi / 4)
    }

    /// Repeated tiled text covering the whole page.
    public static func tiledText(_ text: String, font: UIFont = .systemFont(ofSize: 22),
                                 color: UIColor = .gray, opacity: CGFloat = 0.18) -> Watermark {
        Watermark(content: .text(text, font: font, color: color),
                  layout: .tiled(spacing: CGSize(width: 60, height: 120)),
                  opacity: opacity, rotation: -.pi / 6)
    }

    /// Small text in the bottom-right corner (footer-style).
    public static func cornerText(_ text: String, font: UIFont = .systemFont(ofSize: 14),
                                  color: UIColor = .gray, opacity: CGFloat = 0.6,
                                  corner: Layout = .bottomRight) -> Watermark {
        Watermark(content: .text(text, font: font, color: color), layout: corner, opacity: opacity)
    }

    /// Centered logo/image watermark.
    public static func image(_ image: UIImage, layout: Layout = .centered,
                             opacity: CGFloat = 0.25, scale: CGFloat = 1, rotation: CGFloat = 0) -> Watermark {
        Watermark(content: .image(image), layout: layout, opacity: opacity, rotation: rotation, scale: scale)
    }

    // MARK: - Drawing (call within a UIKit graphics context, e.g. UIGraphicsPDFRenderer)

    /// One watermark instance's size at the current scale.
    private var unitSize: CGSize {
        switch content {
        case let .text(string, font, _):
            return (string as NSString).size(withAttributes: [.font: font.withSize(font.pointSize * scale)])
        case let .image(image):
            return CGSize(width: image.size.width * scale, height: image.size.height * scale)
        }
    }

    public func draw(in bounds: CGRect) {
        switch layout {
        case .centered:
            drawInstance(at: CGPoint(x: bounds.midX, y: bounds.midY))
        case let .tiled(spacing):
            let unit = unitSize
            let stepX = max(1, unit.width + spacing.width)
            let stepY = max(1, unit.height + spacing.height)
            var y = bounds.minY + stepY / 2
            while y < bounds.maxY {
                var x = bounds.minX + stepX / 2
                while x < bounds.maxX { drawInstance(at: CGPoint(x: x, y: y)); x += stepX }
                y += stepY
            }
        case .topLeft:
            drawInstance(at: CGPoint(x: bounds.minX + inset + unitSize.width / 2, y: bounds.minY + inset + unitSize.height / 2))
        case .topRight:
            drawInstance(at: CGPoint(x: bounds.maxX - inset - unitSize.width / 2, y: bounds.minY + inset + unitSize.height / 2))
        case .bottomLeft:
            drawInstance(at: CGPoint(x: bounds.minX + inset + unitSize.width / 2, y: bounds.maxY - inset - unitSize.height / 2))
        case .bottomRight:
            drawInstance(at: CGPoint(x: bounds.maxX - inset - unitSize.width / 2, y: bounds.maxY - inset - unitSize.height / 2))
        }
    }

    private func drawInstance(at point: CGPoint) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let unit = unitSize
        ctx.saveGState()
        ctx.translateBy(x: point.x, y: point.y)
        ctx.rotate(by: rotation)
        let rect = CGRect(x: -unit.width / 2, y: -unit.height / 2, width: unit.width, height: unit.height)
        switch content {
        case let .text(string, font, color):
            (string as NSString).draw(in: rect, withAttributes: [
                .font: font.withSize(font.pointSize * scale),
                .foregroundColor: color.withAlphaComponent(opacity),
            ])
        case let .image(image):
            image.draw(in: rect, blendMode: .normal, alpha: opacity)
        }
        ctx.restoreGState()
    }
}

public extension PDFDocument {

    /// Burn `watermark` into every page and return the new PDF data. Page
    /// vector content is preserved (re-drawn via `drawPDFPage`).
    func watermarkedData(_ watermark: Watermark) -> Data? {
        guard pageCount > 0, let first = page(at: 0) else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: first.bounds(for: .mediaBox))
        return renderer.pdfData { ctx in
            for index in 0..<pageCount {
                guard let page = page(at: index), let ref = page.pageRef else { continue }
                let bounds = page.bounds(for: .mediaBox)
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: bounds.size), pageInfo: [:])
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: bounds.height)   // flip to PDF (y-up) for the page content
                cg.scaleBy(x: 1, y: -1)
                cg.drawPDFPage(ref)
                cg.restoreGState()
                UIGraphicsPushContext(cg)                // watermark in UIKit (y-down) coords, on top
                watermark.draw(in: CGRect(origin: .zero, size: bounds.size))
                UIGraphicsPopContext()
            }
        }
    }

    func watermarked(_ watermark: Watermark) -> PDFDocument? {
        watermarkedData(watermark).flatMap { PDFDocument(data: $0) }
    }

    /// Off-main watermarking for large documents.
    func watermarkedAsync(_ watermark: Watermark) async -> PDFDocument? {
        await Task.detached(priority: .userInitiated) { self.watermarked(watermark) }.value
    }
}

/// A live-overlay page that draws the document's current ``Watermark`` on top —
/// use for an **adjustable preview** (change size/format and re-display) before
/// committing with ``PDFDocument/watermarked(_:)``.
public final class WatermarkPage: PDFPage {
    public override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        guard let watermark = (document as? WatermarkPDFDocument)?.watermark else { return }
        let bounds = self.bounds(for: box)
        UIGraphicsPushContext(context)
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)   // page space (y-up) → UIKit (y-down)
        context.scaleBy(x: 1, y: -1)
        watermark.draw(in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()
        UIGraphicsPopContext()
    }
}

/// A document whose pages are ``WatermarkPage`` — set ``watermark`` for a live,
/// adjustable overlay. Create via ``make(data:watermark:)`` / ``make(url:watermark:)``.
public final class WatermarkPDFDocument: PDFDocument, PDFDocumentDelegate {
    /// Change and re-display (`pdfView.layoutDocumentView()`) to update the preview.
    public var watermark: Watermark?

    public static func make(data: Data, watermark: Watermark? = nil) -> WatermarkPDFDocument? {
        guard let doc = WatermarkPDFDocument(data: data) else { return nil }
        doc.delegate = doc; doc.watermark = watermark
        return doc
    }

    public static func make(url: URL, watermark: Watermark? = nil) -> WatermarkPDFDocument? {
        guard let doc = WatermarkPDFDocument(url: url) else { return nil }
        doc.delegate = doc; doc.watermark = watermark
        return doc
    }

    public func classForPage() -> AnyClass { WatermarkPage.self }
}

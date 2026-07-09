//
//  PDFBuilder.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 02/07/2026.
//

import PDFKit
import UIKit

/// A positioned text run to embed as an invisible, selectable layer — usually
/// built from Vision OCR results (normalized box, origin bottom-left).
public struct PDFTextRun: Sendable {
    public let text: String
    /// Normalized `0...1` box in Vision coordinates (origin bottom-left).
    public let boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// One page: the scanned image plus optional OCR runs for the hidden text layer.
public struct PDFPageContent {
    public let image: UIImage
    public let textRuns: [PDFTextRun]

    public init(image: UIImage, textRuns: [PDFTextRun] = []) {
        self.image = image
        self.textRuns = textRuns
    }
}

/// Builds PDFs from scanned images — plain image pages, or **searchable** pages
/// with an invisible text layer aligned to recognized text.
public enum PDFBuilder {
    /// A simple image-only PDF (not searchable).
    public static func imagePDF(from images: [UIImage]) -> PDFDocument {
        let document = PDFDocument()
        for (index, image) in images.enumerated() {
            if let page = PDFPage(image: image) {
                document.insert(page, at: index)
            }
        }
        return document
    }

    /// A searchable PDF: each page draws the image plus an invisible text layer,
    /// so the result is selectable and full-text searchable.
    public static func searchablePDFData(pages: [PDFPageContent]) -> Data {
        let defaultBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: defaultBounds)
        return renderer.pdfData { context in
            for page in pages {
                let size = page.image.size
                let bounds = CGRect(origin: .zero, size: size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                page.image.draw(in: bounds)
                for run in page.textRuns {
                    drawInvisibleText(run, imageSize: size)
                }
            }
        }
    }

    public static func searchablePDF(pages: [PDFPageContent]) -> PDFDocument? {
        PDFDocument(data: searchablePDFData(pages: pages))
    }

    /// Off-main searchable-PDF rendering — keeps the UI responsive for many/large pages.
    public static func searchablePDFDataAsync(pages: [PDFPageContent]) async -> Data {
        await Task.detached(priority: .userInitiated) { searchablePDFData(pages: pages) }.value
    }

    public static func searchablePDFAsync(pages: [PDFPageContent]) async -> PDFDocument? {
        PDFDocument(data: await searchablePDFDataAsync(pages: pages))
    }

    // MARK: - Private

    private static func drawInvisibleText(_ run: PDFTextRun, imageSize size: CGSize) {
        guard !run.text.isEmpty else { return }
        let box = run.boundingBox
        // Vision normalized (bottom-left) → UIKit points (top-left).
        let rect = CGRect(
            x: box.minX * size.width,
            y: size.height - (box.minY + box.height) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
        guard rect.width > 1, rect.height > 1 else { return }

        var fontSize = rect.height
        var font = UIFont.systemFont(ofSize: fontSize)
        let measured = (run.text as NSString).size(withAttributes: [.font: font]).width
        if measured > rect.width, measured > 0 {
            fontSize = max(1, fontSize * rect.width / measured)
            font = UIFont.systemFont(ofSize: fontSize)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.clear, // invisible but selectable/searchable
        ]
        (run.text as NSString).draw(in: rect, withAttributes: attributes)
    }
}

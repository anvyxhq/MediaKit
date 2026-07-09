//
//  PDFMarkupView.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import SwiftUI
import PDFKit
import PencilKit

/// A `PDFPage` that remembers a PencilKit drawing so overlay markup survives
/// page recycling. Use together with ``MarkupPDFDocument``.
public final class MarkupPDFPage: PDFPage {
    public var drawing: PKDrawing?
}

/// A `PDFDocument` whose pages are ``MarkupPDFPage`` instances (so drawings can
/// be attached per page). Create it via ``make(data:)`` / ``make(url:)`` so the
/// page class is registered before any page is accessed.
public final class MarkupPDFDocument: PDFDocument, PDFDocumentDelegate {

    /// Load PDF data as a markup document. Prefer this over `init(data:)` — it
    /// wires up the delegate that vends ``MarkupPDFPage`` instances.
    public static func make(data: Data) -> MarkupPDFDocument? {
        guard let doc = MarkupPDFDocument(data: data) else { return nil }
        doc.delegate = doc
        return doc
    }

    public static func make(url: URL) -> MarkupPDFDocument? {
        guard let doc = MarkupPDFDocument(url: url) else { return nil }
        doc.delegate = doc
        return doc
    }

    /// PDFDocumentDelegate: use ``MarkupPDFPage`` for every page.
    public func classForPage() -> AnyClass { MarkupPDFPage.self }

    /// Bake every page's overlay drawing into a `.stamp` annotation, then return
    /// flattened PDF data (drawings become permanent page content).
    public func exportWithMarkup(scale: CGFloat = 3) -> Data? {
        for index in 0..<pageCount {
            guard let page = page(at: index) as? MarkupPDFPage,
                  let drawing = page.drawing, !drawing.bounds.isEmpty else { continue }
            let image = drawing.image(from: drawing.bounds, scale: scale)
            page.addAnnotation(StickerAnnotation(image: image, bounds: drawing.bounds))
        }
        let options: [PDFDocumentWriteOption: Any] = [.burnInAnnotationsOption: true]
        return dataRepresentation(options: options)
    }
}

/// A SwiftUI PDF viewer with a PencilKit drawing overlay on every page
/// (iOS 16+ `PDFPageOverlayViewProvider`). Pass a ``MarkupPDFDocument`` so
/// strokes persist and can be exported via ``MarkupPDFDocument/exportWithMarkup()``.
public struct PDFMarkupView: UIViewRepresentable {
    private let document: PDFDocument
    private let tool: PKTool

    public init(
        document: PDFDocument,
        tool: PKTool = PKInkingTool(.pen, color: .systemYellow, width: 12)
    ) {
        self.document = document
        self.tool = tool
    }

    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        context.coordinator.tool = tool
        pdfView.pageOverlayViewProvider = context.coordinator
        return pdfView
    }

    public func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.tool = tool
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator: NSObject, PDFPageOverlayViewProvider {
        var tool: PKTool = PKInkingTool(.pen, color: .systemYellow, width: 12) {
            didSet { canvases.values.forEach { $0.tool = tool } }
        }
        private var canvases: [PDFPage: PKCanvasView] = [:]

        public func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            let canvas: PKCanvasView
            if let existing = canvases[page] {
                canvas = existing
            } else {
                canvas = PKCanvasView()
                canvas.drawingPolicy = .anyInput
                canvas.backgroundColor = .clear
                canvas.tool = tool
                canvases[page] = canvas
            }
            if let markup = page as? MarkupPDFPage, let drawing = markup.drawing {
                canvas.drawing = drawing
            }
            return canvas
        }

        public func pdfView(
            _ view: PDFView,
            willEndDisplayingOverlayView overlayView: UIView,
            for page: PDFPage
        ) {
            guard let canvas = overlayView as? PKCanvasView else { return }
            (page as? MarkupPDFPage)?.drawing = canvas.drawing
            canvases[page] = nil
        }
    }
}

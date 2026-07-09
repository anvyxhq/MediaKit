//
//  PDFViewerSwiftUI.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import SwiftUI
import PDFKit
import Observation

/// Owns a `PDFView` and exposes it to SwiftUI, so a viewer and a thumbnail strip
/// can share the same underlying view.
@MainActor
@Observable
public final class PDFViewer {
    public let pdfView = PDFView()

    public init(document: PDFDocument? = nil) {
        pdfView.document = document
        pdfView.autoScales = true
    }

    public var document: PDFDocument? {
        get { pdfView.document }
        set { pdfView.document = newValue }
    }

    /// Enable the system Find bar (⌘F).
    public func enableFind() { pdfView.enableSystemFind() }
    public func presentFind() { pdfView.presentFind() }

    /// Jump to a table-of-contents entry.
    public func go(to item: PDFTOCItem) { pdfView.go(to: item) }
}

/// SwiftUI PDF viewer.
public struct PDFKitView: UIViewRepresentable {
    private let viewer: PDFViewer
    public init(_ viewer: PDFViewer) { self.viewer = viewer }
    public func makeUIView(context: Context) -> PDFView { viewer.pdfView }
    public func updateUIView(_ uiView: PDFView, context: Context) {}
}

/// SwiftUI thumbnail strip bound to a ``PDFViewer`` (tapping a thumbnail scrolls
/// the viewer). Wraps PDFKit's `PDFThumbnailView`.
public struct PDFThumbnailStrip: UIViewRepresentable {
    private let viewer: PDFViewer
    private let thumbnailSize: CGSize
    private let horizontal: Bool
    private let background: UIColor

    public init(_ viewer: PDFViewer,
                thumbnailSize: CGSize = CGSize(width: 44, height: 58),
                horizontal: Bool = true,
                background: UIColor = .clear) {
        self.viewer = viewer
        self.thumbnailSize = thumbnailSize
        self.horizontal = horizontal
        self.background = background
    }

    public func makeUIView(context: Context) -> PDFThumbnailView {
        let thumb = PDFThumbnailView()
        thumb.pdfView = viewer.pdfView
        thumb.thumbnailSize = thumbnailSize
        thumb.layoutMode = horizontal ? .horizontal : .vertical
        thumb.backgroundColor = background
        return thumb
    }

    public func updateUIView(_ uiView: PDFThumbnailView, context: Context) {
        uiView.pdfView = viewer.pdfView
        uiView.thumbnailSize = thumbnailSize
        uiView.layoutMode = horizontal ? .horizontal : .vertical
    }
}

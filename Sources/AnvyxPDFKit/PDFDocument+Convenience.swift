//
//  PDFDocument+Convenience.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 02/07/2026.
//

import PDFKit
import UIKit

public extension PDFDocument {
    /// Merge several documents into one, preserving page order.
    static func merged(_ documents: [PDFDocument]) -> PDFDocument {
        let result = PDFDocument()
        var index = 0
        for document in documents {
            for pageIndex in 0..<document.pageCount {
                if let page = document.page(at: pageIndex)?.copy() as? PDFPage {
                    result.insert(page, at: index)
                    index += 1
                }
            }
        }
        return result
    }

    /// Append another document's pages to this one.
    func append(_ other: PDFDocument) {
        for pageIndex in 0..<other.pageCount {
            if let page = other.page(at: pageIndex)?.copy() as? PDFPage {
                insert(page, at: pageCount)
            }
        }
    }

    /// Full extracted text (empty string when the PDF has no text layer).
    var fullText: String { string ?? "" }

    /// Render a page to a thumbnail image.
    func thumbnail(page index: Int, size: CGSize) -> UIImage? {
        guard let page = page(at: index) else { return nil }
        return page.thumbnail(of: size, for: .mediaBox)
    }

    /// Off-main thumbnail rendering (for large pages / grids).
    func thumbnailAsync(page index: Int, size: CGSize) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { self.thumbnail(page: index, size: size) }.value
    }

    /// A password-protected copy of this document.
    func encrypted(userPassword: String, ownerPassword: String? = nil) -> PDFDocument? {
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: userPassword,
            .ownerPasswordOption: ownerPassword ?? userPassword,
        ]
        guard let data = dataRepresentation(options: options) else { return nil }
        return PDFDocument(data: data)
    }
}

//
//  PDFOutline.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import PDFKit

/// A flattened table-of-contents entry (from the PDF's outline / bookmarks).
public struct PDFTOCItem: Identifiable {
    public let id = UUID()
    public let label: String
    public let level: Int
    public let pageIndex: Int?
    public let destination: PDFDestination?
}

public extension PDFDocument {

    /// The document's table of contents, flattened depth-first with indent `level`.
    /// Empty when the PDF has no outline.
    func tableOfContents() -> [PDFTOCItem] {
        guard let root = outlineRoot else { return [] }
        var items: [PDFTOCItem] = []
        func walk(_ node: PDFOutline, level: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                var pageIndex: Int?
                if let page = child.destination?.page { pageIndex = index(for: page) }
                items.append(PDFTOCItem(label: child.label ?? "",
                                        level: level,
                                        pageIndex: pageIndex,
                                        destination: child.destination))
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 0)
        return items
    }
}

public extension PDFView {
    /// Navigate to a table-of-contents entry.
    func go(to item: PDFTOCItem) {
        if let destination = item.destination { go(to: destination) }
    }
}

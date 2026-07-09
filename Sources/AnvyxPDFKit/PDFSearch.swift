//
//  PDFSearch.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import PDFKit
import UIKit

/// A single search hit in a document.
public struct PDFSearchMatch {
    public let pageIndex: Int
    public let string: String
    /// The underlying selection — pass to a `PDFView` to highlight / scroll to.
    public let selection: PDFSelection

    /// The hit's bounding box in its page's coordinate space.
    public var bounds: CGRect {
        selection.pages.first.map { selection.bounds(for: $0) } ?? .zero
    }
}

public extension PDFDocument {

    /// Find every occurrence of `query` (case-insensitive by default). Empty
    /// query returns `[]`.
    func matches(of query: String, options: NSString.CompareOptions = .caseInsensitive) -> [PDFSearchMatch] {
        guard !query.isEmpty else { return [] }
        return findString(query, withOptions: options).compactMap { selection in
            guard let page = selection.pages.first else { return nil }
            return PDFSearchMatch(pageIndex: index(for: page),
                                  string: selection.string ?? query,
                                  selection: selection)
        }
    }

    /// Off-main search — full-document `findString` can be slow on large PDFs.
    func matchesAsync(of query: String, options: NSString.CompareOptions = .caseInsensitive) async -> [PDFSearchMatch] {
        await Task.detached(priority: .userInitiated) { self.matches(of: query, options: options) }.value
    }

    /// The next match after `selection` (or the first if `selection` is nil).
    /// Pass `.backwards` in `options` to search upward.
    func nextMatch(of query: String, after selection: PDFSelection?,
                   options: NSString.CompareOptions = .caseInsensitive) -> PDFSearchMatch? {
        guard !query.isEmpty else { return nil }
        guard let found = findString(query, fromSelection: selection, withOptions: options),
              let page = found.pages.first else { return nil }
        return PDFSearchMatch(pageIndex: index(for: page), string: found.string ?? query, selection: found)
    }
}

public extension PDFView {

    /// Enable the system Find bar (⌘F / long-press → Find). iOS 16+.
    func enableSystemFind() {
        isFindInteractionEnabled = true
    }

    /// Programmatically present the system find navigator.
    func presentFind() {
        if !isFindInteractionEnabled { isFindInteractionEnabled = true }
        findInteraction.presentFindNavigator(showingReplace: false)
    }

    /// Highlight `matches` and optionally scroll to / select the one at `current`.
    func highlight(_ matches: [PDFSearchMatch], current: Int? = nil, color: UIColor = .systemYellow) {
        highlightedSelections = matches.map { $0.selection }
        guard let current, matches.indices.contains(current) else { return }
        let selection = matches[current].selection
        selection.color = color
        setCurrentSelection(selection, animate: true)
        go(to: selection)
    }

    /// Clear all search highlights.
    func clearHighlights() {
        highlightedSelections = nil
    }
}

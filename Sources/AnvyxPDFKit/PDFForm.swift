//
//  PDFForm.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import PDFKit

/// Read, fill, and flatten AcroForm fields (widget annotations) in a PDF.
///
/// Buttons (checkbox/radio) are represented as `"on"` / `"off"`; text and
/// choice fields as their string value. Fields are matched by `fieldName`.
public enum PDFForm {

    /// All form field values keyed by `fieldName`.
    public static func fields(in document: PDFDocument) -> [String: String] {
        var values: [String: String] = [:]
        forEachWidget(in: document) { name, annotation in
            values[name] = value(of: annotation)
        }
        return values
    }

    /// Whether the document contains any form fields.
    public static func hasForm(_ document: PDFDocument) -> Bool {
        var found = false
        forEachWidget(in: document) { _, _ in found = true }
        return found
    }

    /// Fill fields by `fieldName`. Missing names are ignored. For buttons pass
    /// `"on"`/`"off"` (or `"true"`/`"false"`).
    public static func fill(_ document: PDFDocument, values: [String: String]) {
        forEachWidget(in: document) { name, annotation in
            guard let raw = values[name] else { return }
            if annotation.widgetFieldType == .button {
                let on = raw == "on" || raw.lowercased() == "true"
                annotation.buttonWidgetState = on ? .onState : .offState
            } else {
                annotation.widgetStringValue = raw
            }
        }
    }

    /// Flatten annotations and form fields into page content and return the PDF
    /// data. Irreversible — the result is no longer editable as a form.
    public static func flattened(_ document: PDFDocument) -> Data? {
        let options: [PDFDocumentWriteOption: Any] = [.burnInAnnotationsOption: true]
        return document.dataRepresentation(options: options)
    }

    // MARK: - Private

    private static func value(of annotation: PDFAnnotation) -> String {
        annotation.widgetFieldType == .button
            ? (annotation.buttonWidgetState == .onState ? "on" : "off")
            : (annotation.widgetStringValue ?? "")
    }

    private static func forEachWidget(
        in document: PDFDocument,
        _ body: (_ fieldName: String, _ annotation: PDFAnnotation) -> Void
    ) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                guard let name = annotation.fieldName else { continue } // widgets only
                body(name, annotation)
            }
        }
    }
}

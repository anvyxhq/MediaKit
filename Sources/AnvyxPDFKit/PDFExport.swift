//
//  PDFExport.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import PDFKit
import UIKit
import Vision

/// Render/compression quality for exports.
public enum ExportQuality {
    case low, medium, high, max

    /// Raster scale applied to page size.
    public var scale: CGFloat {
        switch self { case .low: 1.0; case .medium: 1.5; case .high: 2.0; case .max: 3.0 }
    }
    /// JPEG compression quality.
    public var jpegQuality: CGFloat {
        switch self { case .low: 0.4; case .medium: 0.6; case .high: 0.75; case .max: 0.9 }
    }
}

/// One-shot Vision OCR on an image (blocking — call off-main).
private func pdfkitRecognizeText(_ image: UIImage, languages: [String]) -> [VNRecognizedTextObservation] {
    guard let cgImage = image.cgImage else { return [] }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if !languages.isEmpty { request.recognitionLanguages = languages }
    try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
    return request.results ?? []
}

public extension PDFDocument {

    // MARK: - Rendering

    /// Rasterize a page (vector-accurate via `drawPDFPage`) at `scale`.
    func renderedImage(at index: Int, scale: CGFloat = 2) -> UIImage? {
        guard let page = page(at: index), let ref = page.pageRef else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.drawPDFPage(ref)
        }
    }

    /// All pages as images.
    func pageImages(scale: CGFloat = 2) -> [UIImage] {
        (0..<pageCount).compactMap { renderedImage(at: $0, scale: scale) }
    }

    func pageImagesAsync(scale: CGFloat = 2) async -> [UIImage] {
        await Task.detached(priority: .userInitiated) { self.pageImages(scale: scale) }.value
    }

    // MARK: - PDF → JPG

    /// One JPEG per page (fixes the "all pages to one file" pitfall — returns a
    /// `Data` array so the caller writes distinct files).
    func jpegPages(_ quality: ExportQuality = .high) -> [Data] {
        pageImages(scale: quality.scale).compactMap { $0.jpegData(compressionQuality: quality.jpegQuality) }
    }

    func jpegPagesAsync(_ quality: ExportQuality = .high) async -> [Data] {
        await Task.detached(priority: .userInitiated) { self.jpegPages(quality) }.value
    }

    // MARK: - Compress

    /// A size-reduced copy: each page re-encoded as a JPEG at `quality` and
    /// re-wrapped into a PDF (rasterizes — vector/searchable layer is lost).
    func compressedData(_ quality: ExportQuality = .medium) -> Data? {
        var images: [UIImage] = []
        for index in 0..<pageCount {
            guard let rendered = renderedImage(at: index, scale: quality.scale),
                  let data = rendered.jpegData(compressionQuality: quality.jpegQuality),
                  let image = UIImage(data: data) else { continue }
            images.append(image)
        }
        return images.isEmpty ? nil : PDFBuilder.imagePDF(from: images).dataRepresentation()
    }

    func compressedDataAsync(_ quality: ExportQuality = .medium) async -> Data? {
        await Task.detached(priority: .userInitiated) { self.compressedData(quality) }.value
    }

    // MARK: - PDF → TXT (text-layer extraction is `fullText`; OCR below for scans)

    /// OCR every page with Vision and return the recognized text (for scanned
    /// PDFs without a text layer). Runs off-main.
    func recognizedText(languages: [String] = []) async -> String {
        await Task.detached(priority: .userInitiated) {
            var pages: [String] = []
            for index in 0..<self.pageCount {
                guard let image = self.renderedImage(at: index, scale: 2) else { continue }
                let lines = pdfkitRecognizeText(image, languages: languages)
                    .compactMap { $0.topCandidates(1).first?.string }
                pages.append(lines.joined(separator: "\n"))
            }
            return pages.joined(separator: "\n\n")
        }.value
    }

    // MARK: - Live Text OCR → searchable PDF

    /// Turn a scanned PDF into a **searchable** one: OCR each page and embed an
    /// invisible, aligned text layer (via ``PDFBuilder``). Runs off-main.
    func makeSearchable(languages: [String] = [], scale: CGFloat = 2) async -> PDFDocument? {
        await Task.detached(priority: .userInitiated) {
            var pages: [PDFPageContent] = []
            for index in 0..<self.pageCount {
                guard let image = self.renderedImage(at: index, scale: scale) else { continue }
                let runs = pdfkitRecognizeText(image, languages: languages).map {
                    PDFTextRun(text: $0.topCandidates(1).first?.string ?? "", boundingBox: $0.boundingBox)
                }
                pages.append(PDFPageContent(image: image, textRuns: runs))
            }
            return PDFBuilder.searchablePDF(pages: pages)
        }.value
    }
}

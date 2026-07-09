//
//  PDFKitWrapperTests.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 02/07/2026.
//

import XCTest
import PDFKit
import UIKit
@testable import PDFKitWrapper

@MainActor
final class PDFKitWrapperTests: XCTestCase {
    private func solidImage(_ size: CGSize = CGSize(width: 200, height: 300)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testImagePDFPageCount() {
        let pdf = PDFBuilder.imagePDF(from: [solidImage(), solidImage()])
        XCTAssertEqual(pdf.pageCount, 2)
    }

    func testSearchablePDFEmbedsText() {
        let run = PDFTextRun(text: "Snapfolio", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.6, height: 0.08))
        let page = PDFPageContent(image: solidImage(), textRuns: [run])
        let pdf = PDFBuilder.searchablePDF(pages: [page])
        XCTAssertEqual(pdf?.pageCount, 1)
        XCTAssertTrue((pdf?.fullText ?? "").contains("Snapfolio"))
    }

    func testMerge() {
        let a = PDFBuilder.imagePDF(from: [solidImage()])
        let b = PDFBuilder.imagePDF(from: [solidImage(), solidImage()])
        XCTAssertEqual(PDFDocument.merged([a, b]).pageCount, 3)
    }

    func testAnnotationFactoryAndFlatten() {
        let pdf = PDFBuilder.imagePDF(from: [solidImage()])
        guard let page = pdf.page(at: 0) else { return XCTFail("no page") }
        let bounds = page.bounds(for: .mediaBox)

        page.addAnnotation(.freeText("Hi", bounds: CGRect(x: 10, y: 10, width: 80, height: 20)))
        let path = UIBezierPath(); path.move(to: .zero); path.addLine(to: CGPoint(x: 50, y: 50))
        page.addAnnotation(.ink(paths: [path], bounds: bounds))
        page.addAnnotation(.imageStamp(solidImage(CGSize(width: 40, height: 40)),
                                       bounds: CGRect(x: 10, y: 100, width: 40, height: 40)))
        XCTAssertEqual(page.annotations.count, 3)

        XCTAssertNotNil(PDFForm.flattened(pdf))
    }

    func testFormReadFillRoundTrip() {
        let pdf = PDFBuilder.imagePDF(from: [solidImage()])
        guard let page = pdf.page(at: 0) else { return XCTFail("no page") }
        let field = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 120, height: 24),
                                  forType: .widget, withProperties: nil)
        field.widgetFieldType = .text
        field.fieldName = "name"
        page.addAnnotation(field)

        XCTAssertTrue(PDFForm.hasForm(pdf))
        PDFForm.fill(pdf, values: ["name": "AnhPT"])
        XCTAssertEqual(PDFForm.fields(in: pdf)["name"], "AnhPT")
    }

    func testTemporaryFileURLWritesFile() {
        let pdf = PDFBuilder.imagePDF(from: [solidImage()])
        guard let url = pdf.temporaryFileURL(named: "test.pdf") else { return XCTFail("no url") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    func testTableOfContentsEmptyForGeneratedPDF() {
        let pdf = PDFBuilder.imagePDF(from: [solidImage()])
        XCTAssertTrue(pdf.tableOfContents().isEmpty)   // generated PDFs have no outline
    }

    func testPDFViewerDocumentBinding() {
        let pdf = PDFBuilder.imagePDF(from: [solidImage(), solidImage()])
        let viewer = PDFViewer(document: pdf)
        XCTAssertEqual(viewer.document?.pageCount, 2)
    }

    func testExportImagesAndJPEGAndCompress() {
        let pdf = PDFBuilder.imagePDF(from: [solidImage(), solidImage()])
        XCTAssertEqual(pdf.pageImages(scale: 1).count, 2)
        XCTAssertEqual(pdf.jpegPages(.medium).count, 2)
        let compressed = pdf.compressedData(.low)
        XCTAssertNotNil(compressed)
        XCTAssertEqual(PDFDocument(data: compressed!)?.pageCount, 2)
    }

    func testMakeSearchableKeepsPageCount() async {
        let pdf = PDFBuilder.imagePDF(from: [solidImage()])
        let searchable = await pdf.makeSearchable()   // blank page → empty OCR, still a valid doc
        XCTAssertEqual(searchable?.pageCount, 1)
    }

    func testWatermarkPresetsProduceDocument() {
        let base = PDFBuilder.imagePDF(from: [solidImage(), solidImage()])
        for wm in [Watermark.diagonalText("CONFIDENTIAL"),
                   .tiledText("DRAFT"),
                   .cornerText("© Anvora"),
                   .image(solidImage(CGSize(width: 40, height: 40)), scale: 0.5)] {
            let out = base.watermarked(wm)
            XCTAssertEqual(out?.pageCount, 2)
        }
    }

    func testWatermarkPageDocument() {
        let base = PDFBuilder.imagePDF(from: [solidImage()])
        guard let data = base.dataRepresentation(),
              let doc = WatermarkPDFDocument.make(data: data, watermark: .diagonalText("X")) else { return XCTFail() }
        XCTAssertTrue(doc.page(at: 0) is WatermarkPage)
        doc.watermark = .tiledText("Y")   // adjustable
        XCTAssertNotNil(doc.watermark)
    }

    func testSearchFindsMatches() {
        let run = PDFTextRun(text: "Snapfolio", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.6, height: 0.08))
        let page = PDFPageContent(image: solidImage(), textRuns: [run])
        guard let pdf = PDFBuilder.searchablePDF(pages: [page, page]) else { return XCTFail("no pdf") }
        let matches = pdf.matches(of: "snapfolio")   // case-insensitive
        XCTAssertGreaterThanOrEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.pageIndex, 0)
        XCTAssertEqual(pdf.matches(of: "").count, 0)
    }

    func testStampHelperAddsStickerAnnotation() {
        let pdf = PDFBuilder.imagePDF(from: [solidImage()])
        guard let page = pdf.page(at: 0) else { return XCTFail("no page") }
        let pdfView = PDFView()
        pdfView.document = pdf
        page.stamp(image: solidImage(CGSize(width: 40, height: 40)),
                   frame: CGRect(x: 0, y: 0, width: 40, height: 40),
                   in: pdfView, rotation: .pi / 6, scale: 1.2)
        XCTAssertEqual(page.annotations.count, 1)
        XCTAssertTrue(page.annotations.first is StickerAnnotation)
    }

    func testMarkupDocumentVendsMarkupPages() {
        let base = PDFBuilder.imagePDF(from: [solidImage()])
        guard let data = base.dataRepresentation(),
              let doc = MarkupPDFDocument.make(data: data) else { return XCTFail("no data") }
        XCTAssertTrue(doc.page(at: 0) is MarkupPDFPage)
    }
}

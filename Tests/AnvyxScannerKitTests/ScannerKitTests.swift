//
//  ScannerKitTests.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import UIKit
import AnvyxCropKit
@testable import AnvyxScannerKit

final class ScannerKitTests: XCTestCase {

    private func rectangleImage() -> CGImage {
        let size = CGSize(width: 400, height: 300)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let rect = CGRect(x: 60, y: 50, width: 280, height: 200)
            UIColor(white: 0.85, alpha: 1).setFill(); UIBezierPath(rect: rect).fill()
            UIColor.black.setStroke()
            let border = UIBezierPath(rect: rect); border.lineWidth = 6; border.stroke()
        }.cgImage!
    }

    func testDocumentDetectorFindsRectangleWithNormalizedCorners() throws {
        let detector = DocumentQuadDetector(minimumConfidence: 0.0, minimumAspectRatio: 0.2, minimumSize: 0.05)
        let quads = try detector.detect(in: rectangleImage())
        XCTAssertFalse(quads.isEmpty, "expected to detect the drawn rectangle")
        for quad in quads {
            for point in [quad.topLeft, quad.topRight, quad.bottomLeft, quad.bottomRight] {
                XCTAssertTrue((0...1).contains(point.x), "x out of range: \(point.x)")
                XCTAssertTrue((0...1).contains(point.y), "y out of range: \(point.y)")
            }
        }
    }

    func testDocumentDetectorHonorsMaximum() throws {
        let quads = try DocumentQuadDetector(maximumDocuments: 1, minimumConfidence: 0.0, minimumSize: 0.05)
            .detect(in: rectangleImage())
        XCTAssertLessThanOrEqual(quads.count, 1)
    }

    func testTextDetectorReturnsEmptyOnBlank() throws {
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }.cgImage!
        XCTAssertTrue(try TextLineDetector().detect(in: blank).isEmpty)
    }

    func testCorrectedCropFromDetectedQuad() throws {
        let source = rectangleImage()
        let quad = try XCTUnwrap(try DocumentQuadDetector(minimumConfidence: 0.0, minimumSize: 0.05)
            .detect(in: source).first)
        let corrected = DocumentPerspective.corrected(source, quad: quad)
        XCTAssertNotNil(corrected, "perspective correction should produce an image")
    }

    @MainActor
    func testLiveScannerDefaults() {
        let scanner = LiveScanner(mode: .document, maximumDocuments: 2)
        XCTAssertEqual(scanner.mode, .document)
        XCTAssertTrue(scanner.quads.isEmpty)
        XCTAssertTrue(scanner.textLines.isEmpty)
    }
}

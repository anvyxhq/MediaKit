//
//  DocumentEdgeDetectionTests.swift
//  CropKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import UIKit
@testable import AnvyxCropKit

final class DocumentEdgeDetectionTests: XCTestCase {

    private func image(_ size: CGSize = CGSize(width: 200, height: 200)) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 40, y: 40, width: 120, height: 120))
        }.cgImage!
    }

    func testPerspectiveCorrectionFlattensQuad() throws {
        let source = image()   // 200×200
        // A centered 80%-inset quad (normalized, bottom-left origin).
        let quad = DocumentQuad(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomLeft: CGPoint(x: 0.1, y: 0.1),
            bottomRight: CGPoint(x: 0.9, y: 0.1))

        let corrected = try XCTUnwrap(DocumentPerspective.corrected(source, quad: quad))
        // 0.8 * 200 = 160 on each side (allow rounding).
        XCTAssertEqual(Double(corrected.width), 160, accuracy: 2)
        XCTAssertEqual(Double(corrected.height), 160, accuracy: 2)
    }

    func testPerspectiveCorrectionSkewedQuadProducesImage() throws {
        let source = image()
        let quad = DocumentQuad(
            topLeft: CGPoint(x: 0.05, y: 0.95),
            topRight: CGPoint(x: 0.85, y: 0.9),
            bottomLeft: CGPoint(x: 0.1, y: 0.1),
            bottomRight: CGPoint(x: 0.9, y: 0.15))
        XCTAssertNotNil(DocumentPerspective.corrected(source, quad: quad))
    }

    func testDetectorRunsWithoutCrashing() async throws {
        guard #available(iOS 26, *) else { throw XCTSkip("DocumentEdgeDetector requires iOS 26") }
        // A synthetic image may or may not be detected as a document; the point is
        // the request runs and returns an optional safely.
        _ = try await DocumentEdgeDetector().detectQuad(in: image())
    }
}

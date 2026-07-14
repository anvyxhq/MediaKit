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

    @MainActor
    func testSingleDocumentModeInit() {
        let scanner = LiveScanner(mode: .singleDocument)
        XCTAssertEqual(scanner.mode, .singleDocument)
    }

    @MainActor
    func testAutoCaptureToggle() {
        let scanner = LiveScanner(mode: .document, autoCapture: true)
        XCTAssertTrue(scanner.autoCaptureEnabled)
        scanner.autoCaptureEnabled = false
        XCTAssertFalse(scanner.autoCaptureEnabled)
    }

    private func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        return buffer!
    }

    func testAnalysisImageDownscalesLargeFrame() {
        let large = pixelBuffer(width: 4032, height: 3024)
        let image = LiveScanner.analysisImage(from: large, orientation: .up, maxDimension: 1024)
        XCTAssertLessThanOrEqual(max(image.extent.width, image.extent.height), 1024)
        XCTAssertEqual(image.extent.width / image.extent.height, 4.0 / 3.0, accuracy: 0.02)
    }

    func testAnalysisImageKeepsSmallFrame() {
        let small = pixelBuffer(width: 640, height: 480)
        let image = LiveScanner.analysisImage(from: small, orientation: .up, maxDimension: 1024)
        XCTAssertEqual(image.extent.width, 640)
        XCTAssertEqual(image.extent.height, 480)
    }

    private func filledBuffer(width: Int, height: Int, gray: UInt8) -> CVPixelBuffer {
        let buffer = pixelBuffer(width: width, height: height)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(gray), CVPixelBufferGetBytesPerRow(buffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    func testAverageBrightness() {
        XCTAssertEqual(FrameQuality.averageBrightness(of: filledBuffer(width: 96, height: 96, gray: 0)), 0, accuracy: 0.02)
        XCTAssertEqual(FrameQuality.averageBrightness(of: filledBuffer(width: 96, height: 96, gray: 255)), 1, accuracy: 0.02)
        XCTAssertEqual(FrameQuality.averageBrightness(of: filledBuffer(width: 96, height: 96, gray: 128)), 0.5, accuracy: 0.03)
    }

    func testQuadArea() {
        let full = DocumentQuad(topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 1),
                                bottomLeft: CGPoint(x: 0, y: 0), bottomRight: CGPoint(x: 1, y: 0))
        XCTAssertEqual(FrameQuality.area(of: full), 1.0, accuracy: 0.001)
        let half = DocumentQuad(topLeft: CGPoint(x: 0.25, y: 0.75), topRight: CGPoint(x: 0.75, y: 0.75),
                                bottomLeft: CGPoint(x: 0.25, y: 0.25), bottomRight: CGPoint(x: 0.75, y: 0.25))
        XCTAssertEqual(FrameQuality.area(of: half), 0.25, accuracy: 0.001)
    }

    func testPerfMetricsReturnValues() {
        XCTAssertGreaterThan(PerfMetrics.memoryFootprintBytes(), 0)
        XCTAssertGreaterThanOrEqual(PerfMetrics.cpuUsagePercent(), 0)
    }

    func testGuidanceMessagesNonEmpty() {
        let cases: [ScanGuidance] = [.searching, .tooDark, .tooBright, .moveCloser, .moveAway, .holdSteady, .ready]
        for guidance in cases { XCTAssertFalse(guidance.message.isEmpty) }
    }

    func testVisionOrientationMapping() {
        XCTAssertEqual(LiveScanner.visionOrientation(device: .portrait, position: .back), .right)
        XCTAssertEqual(LiveScanner.visionOrientation(device: .landscapeLeft, position: .back), .up)
        XCTAssertEqual(LiveScanner.visionOrientation(device: .landscapeRight, position: .back), .down)
        XCTAssertEqual(LiveScanner.visionOrientation(device: .portraitUpsideDown, position: .back), .left)
        // Front camera mirrors horizontally.
        XCTAssertEqual(LiveScanner.visionOrientation(device: .portrait, position: .front), .leftMirrored)
    }
}

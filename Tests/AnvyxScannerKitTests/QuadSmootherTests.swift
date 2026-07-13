//
//  QuadSmootherTests.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import CoreGraphics
import AnvyxCropKit
@testable import AnvyxScannerKit

final class QuadSmootherTests: XCTestCase {

    private func quad(cx: CGFloat, cy: CGFloat, half: CGFloat = 0.1) -> DocumentQuad {
        DocumentQuad(
            topLeft: CGPoint(x: cx - half, y: cy + half),
            topRight: CGPoint(x: cx + half, y: cy + half),
            bottomLeft: CGPoint(x: cx - half, y: cy - half),
            bottomRight: CGPoint(x: cx + half, y: cy - half))
    }

    func testFirstUpdatePassesThrough() {
        var smoother = QuadSmoother(smoothing: 0.5)
        let q = quad(cx: 0.5, cy: 0.5)
        XCTAssertEqual(smoother.update([q]), [q])
    }

    func testZeroSmoothingSnaps() {
        var smoother = QuadSmoother(smoothing: 0)
        _ = smoother.update([quad(cx: 0.5, cy: 0.5)])
        let moved = quad(cx: 0.55, cy: 0.55)
        XCTAssertEqual(smoother.update([moved]), [moved])
    }

    func testMatchedQuadBlendsTowardPrevious() {
        var smoother = QuadSmoother(smoothing: 0.5, matchDistance: 0.2)
        _ = smoother.update([quad(cx: 0.50, cy: 0.50)])
        let result = smoother.update([quad(cx: 0.60, cy: 0.50)])
        // With 0.5 weight the smoothed centroid should land between 0.50 and 0.60.
        let cx = QuadSmoother.centroid(result[0]).x
        XCTAssertGreaterThan(cx, 0.50)
        XCTAssertLessThan(cx, 0.60)
        XCTAssertEqual(cx, 0.55, accuracy: 0.001)
    }

    func testDistantQuadSnapsInsteadOfBlending() {
        var smoother = QuadSmoother(smoothing: 0.9, matchDistance: 0.1)
        _ = smoother.update([quad(cx: 0.2, cy: 0.2)])
        let far = quad(cx: 0.8, cy: 0.8)   // beyond matchDistance → treated as new
        XCTAssertEqual(smoother.update([far]), [far])
    }

    func testResetClearsHistory() {
        var smoother = QuadSmoother(smoothing: 0.9)
        _ = smoother.update([quad(cx: 0.5, cy: 0.5)])
        smoother.reset()
        let next = quad(cx: 0.52, cy: 0.52)
        XCTAssertEqual(smoother.update([next]), [next])   // no history → passes through
    }
}

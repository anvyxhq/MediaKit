//
//  QuadTrackerTests.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import CoreGraphics
import AnvyxCropKit
@testable import AnvyxScannerKit

final class QuadTrackerTests: XCTestCase {

    private func scored(cx: CGFloat, cy: CGFloat, confidence: Float, half: CGFloat = 0.1) -> ScoredQuad {
        ScoredQuad(quad: DocumentQuad(
            topLeft: CGPoint(x: cx - half, y: cy + half),
            topRight: CGPoint(x: cx + half, y: cy + half),
            bottomLeft: CGPoint(x: cx - half, y: cy - half),
            bottomRight: CGPoint(x: cx + half, y: cy - half)), confidence: confidence)
    }

    func testLowConfidenceDoesNotAppear() {
        var tracker = QuadTracker(enterConfidence: 0.7, keepConfidence: 0.4)
        let result = tracker.update([scored(cx: 0.5, cy: 0.5, confidence: 0.5)])
        XCTAssertTrue(result.isEmpty, "below enter threshold should not show")
    }

    func testHysteresisKeepsVisibleUntilBelowKeep() {
        var tracker = QuadTracker(enterConfidence: 0.7, keepConfidence: 0.4, graceFrames: 0)
        XCTAssertEqual(tracker.update([scored(cx: 0.5, cy: 0.5, confidence: 0.8)]).count, 1)  // enters
        // Confidence dips between keep and enter → stays visible (hysteresis).
        XCTAssertEqual(tracker.update([scored(cx: 0.5, cy: 0.5, confidence: 0.5)]).count, 1)
        // Drops below keep → hides.
        XCTAssertEqual(tracker.update([scored(cx: 0.5, cy: 0.5, confidence: 0.3)]).count, 0)
    }

    func testGraceFramesSurviveBriefMiss() {
        var tracker = QuadTracker(enterConfidence: 0.7, keepConfidence: 0.4, graceFrames: 3)
        XCTAssertEqual(tracker.update([scored(cx: 0.5, cy: 0.5, confidence: 0.9)]).count, 1)
        // Two frames with no detection — held by grace.
        XCTAssertEqual(tracker.update([]).count, 1)
        XCTAssertEqual(tracker.update([]).count, 1)
    }

    func testDropsAfterGraceExhausted() {
        var tracker = QuadTracker(enterConfidence: 0.7, keepConfidence: 0.4, graceFrames: 1)
        _ = tracker.update([scored(cx: 0.5, cy: 0.5, confidence: 0.9)])
        XCTAssertEqual(tracker.update([]).count, 1)   // grace frame 1
        XCTAssertEqual(tracker.update([]).count, 0)   // grace exhausted
    }

    func testResetClears() {
        var tracker = QuadTracker(enterConfidence: 0.5)
        _ = tracker.update([scored(cx: 0.5, cy: 0.5, confidence: 0.9)])
        tracker.reset()
        XCTAssertEqual(tracker.update([]).count, 0)
    }
}

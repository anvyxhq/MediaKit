//
//  CameraZoomLayoutTests.swift
//  CameraKit
//
//  Created by AnhPT on 13/11/2026.
//

import XCTest
@testable import AnvyxCameraKit

final class CameraZoomLayoutTests: XCTestCase {
    // ultra-wide → wide at 2.0, wide → telephoto at 6.0
    private let triple = CameraZoomLayout(switchOverFactors: [2, 6], wideLensIndex: 1, minZoomFactor: 1, maxZoomFactor: 90)
    // ultra-wide → wide at 2.0
    private let dualWide = CameraZoomLayout(switchOverFactors: [2], wideLensIndex: 1, minZoomFactor: 1, maxZoomFactor: 30)
    // wide → telephoto at 2.0
    private let dual = CameraZoomLayout(switchOverFactors: [2], wideLensIndex: 0, minZoomFactor: 1, maxZoomFactor: 16)
    private let single = CameraZoomLayout(minZoomFactor: 1, maxZoomFactor: 5)

    func testWideLensZoomFactor() {
        XCTAssertEqual(triple.wideLensZoomFactor, 2)
        XCTAssertEqual(dualWide.wideLensZoomFactor, 2)
        XCTAssertEqual(dual.wideLensZoomFactor, 1)
        XCTAssertEqual(single.wideLensZoomFactor, 1)
    }

    func testNextLensZoomFactor() {
        XCTAssertEqual(triple.nextLensZoomFactor, 6)
        XCTAssertNil(dualWide.nextLensZoomFactor)
        XCTAssertEqual(dual.nextLensZoomFactor, 2)
        XCTAssertNil(single.nextLensZoomFactor)
    }

    func testMagnificationMapsOntoWideLens() {
        XCTAssertEqual(triple.zoomFactor(forMagnification: 1), 2)
        XCTAssertEqual(triple.zoomFactor(forMagnification: 0.5), 1)   // ultra-wide
        XCTAssertEqual(triple.zoomFactor(forMagnification: 4), 8)     // crosses to telephoto
        XCTAssertEqual(dual.zoomFactor(forMagnification: 1.5), 1.5)
        XCTAssertEqual(single.zoomFactor(forMagnification: 3), 3)
    }

    func testStayOnWideLensStopsBelowSwitchOver() {
        let capped = triple.zoomFactor(forMagnification: 4, stayOnWideLens: true)
        XCTAssertEqual(capped, 6 * CameraZoomLayout.switchOverMargin, accuracy: 1e-9)
        XCTAssertLessThan(capped, 6)
        // Below the cap the request is honored unchanged.
        XCTAssertEqual(triple.zoomFactor(forMagnification: 1.5, stayOnWideLens: true), 3)
        // Never drops to the ultra-wide lens.
        XCTAssertEqual(triple.zoomFactor(forMagnification: 0.5, stayOnWideLens: true), 2)
        // No longer lens: only the device limit applies.
        XCTAssertEqual(dualWide.zoomFactor(forMagnification: 10, stayOnWideLens: true), 20)
        XCTAssertEqual(single.zoomFactor(forMagnification: 3, stayOnWideLens: true), 3)
    }

    func testResultIsClampedToDeviceRange() {
        XCTAssertEqual(triple.zoomFactor(forMagnification: 1000), 90)
        XCTAssertEqual(triple.zoomFactor(forMagnification: 0), 1)
        XCTAssertEqual(triple.zoomFactor(forMagnification: -3), 1)
        XCTAssertEqual(single.zoomFactor(forMagnification: 9), 5)
        XCTAssertEqual(single.clampedZoomFactor(.nan), 1)
        XCTAssertEqual(single.clampedZoomFactor(.infinity), 1)
        XCTAssertEqual(triple.zoomFactor(forMagnification: .nan), 2)

        // The device limit wins when the format cannot reach the wide lens cap.
        let limited = CameraZoomLayout(switchOverFactors: [2, 6], wideLensIndex: 1, minZoomFactor: 1, maxZoomFactor: 4)
        XCTAssertEqual(limited.zoomFactor(forMagnification: 5, stayOnWideLens: true), 4)

        // Degenerate range.
        let fixed = CameraZoomLayout(minZoomFactor: 1, maxZoomFactor: 1)
        XCTAssertEqual(fixed.zoomFactor(forMagnification: 3), 1)
    }

    func testMagnificationRoundTrip() {
        XCTAssertEqual(triple.magnification(forZoomFactor: 2), 1)
        XCTAssertEqual(triple.magnification(forZoomFactor: 1), 0.5)
        XCTAssertEqual(single.magnification(forZoomFactor: 3), 3)
        for magnification: CGFloat in [0.5, 1, 1.7, 3, 10] {
            let factor = triple.zoomFactor(forMagnification: magnification)
            XCTAssertEqual(triple.magnification(forZoomFactor: factor), magnification, accuracy: 1e-9)
        }
        XCTAssertEqual(triple.magnificationRange, 0.5...45)
        XCTAssertEqual(single.magnificationRange, 1...5)
    }

    func testMalformedLayoutFallsBackToPlainFactor() {
        // Wide lens reported but no switch-over factors: treat as a plain lens.
        let odd = CameraZoomLayout(switchOverFactors: [], wideLensIndex: 1, minZoomFactor: 1, maxZoomFactor: 8)
        XCTAssertEqual(odd.wideLensZoomFactor, 1)
        XCTAssertNil(odd.nextLensZoomFactor)
        XCTAssertEqual(odd.zoomFactor(forMagnification: 2, stayOnWideLens: true), 2)

        let zero = CameraZoomLayout(switchOverFactors: [0], wideLensIndex: 1, minZoomFactor: 1, maxZoomFactor: 8)
        XCTAssertEqual(zero.wideLensZoomFactor, 1)
    }
}

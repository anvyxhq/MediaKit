//
//  AdvancedCaptureTests.swift
//  CameraKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import AVFoundation
@testable import AnvyxCameraKit

final class AdvancedCaptureTests: XCTestCase {
    // No camera on the Simulator, so these must be safe no-ops (they guard on the
    // device / output support on the session queue). Real behavior needs a device.
    @MainActor
    func testAdvancedCaptureCallsAreSafeWithoutDevice() {
        let model = CameraModel()

        if #available(iOS 26, *) {
            model.enableCinematicVideo(simulatedAperture: 2.8)
        }
        model.setProRAWEnabled(true)
        if #available(iOS 18, *) {
            model.setConstantColorEnabled(true)
        }
        model.setVideoStabilization(.cinematicExtended)

        // The model is still usable afterwards (nothing trapped).
        XCTAssertEqual(model.position, .back)
    }
}

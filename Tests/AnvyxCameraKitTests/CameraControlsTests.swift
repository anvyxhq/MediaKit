//
//  CameraControlsTests.swift
//  CameraKit
//
//  Created by AnhPT on 10/07/2026.
//

import XCTest
import AVFoundation
@testable import AnvyxCameraKit

final class CameraControlsTests: XCTestCase {
    @MainActor
    func testAddingControlsBeforeConfigureIsSafe() {
        // Hardware Camera Control isn't available on the simulator; the calls must
        // be safe no-ops (they guard on device/canAddControl on the session queue).
        let model = CameraModel()
        model.enableHardwareCameraControls()
        model.addCameraControl {
            AVCaptureSlider("Test", symbolName: "dial.low", in: 0...1)
        }
    }
}

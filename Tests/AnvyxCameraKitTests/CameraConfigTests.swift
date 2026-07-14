//
//  CameraConfigTests.swift
//  CameraKit
//
//  Created by AnhPT on 14/07/2026.
//

import XCTest
import AVFoundation
@testable import AnvyxCameraKit

final class CameraConfigTests: XCTestCase {

    @MainActor
    func testInitialState() {
        let model = CameraModel()
        XCTAssertEqual(model.position, .back)
        XCTAssertFalse(model.isConfigured)
        XCTAssertFalse(model.isRunning)
    }

    @MainActor
    func testFocusAndValidationSafeWithoutDevice() async {
        // No camera on the Simulator, so these must be safe no-ops (guarded on
        // the video input), never trapping.
        let model = CameraModel()
        model.configureForDocumentScanning()
        await model.lockFocusAndExposureWhenStable(timeout: 0.1)
        model.restoreContinuousFocus()
        let trusted = await model.isUsingTrustedCamera()
        XCTAssertFalse(trusted)   // no input configured
        XCTAssertEqual(model.position, .back)
    }

    func testDeviceDetectorDoesNotCrash() {
        let result = CameraDeviceDetector().detect(for: .back)
        _ = result.device
        XCTAssertFalse(result.systemType.description.isEmpty)
    }
}

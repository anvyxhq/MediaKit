//
//  CameraSessionTests.swift
//  CameraKit
//
//  Created by AnhPT on 13/11/2026.
//

import XCTest
import AVFoundation
@testable import AnvyxCameraKit

final class CameraSessionTests: XCTestCase {

    func testAddingAnOutputTwiceFailsWithTypedError() throws {
        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        try CameraModel.add(output, kind: .photo, to: session)
        XCTAssertTrue(session.outputs.contains(output))

        XCTAssertThrowsError(try CameraModel.add(output, kind: .photo, to: session)) { error in
            XCTAssertEqual(error as? CameraError, .cannotAddOutput(.photo))
        }
        XCTAssertEqual(session.outputs.count, 1)
    }

    func testPreferredPresetIsOneTheSessionAccepts() {
        let session = AVCaptureSession()
        CameraModel.applyPreferredPreset(to: session)
        XCTAssertTrue(session.canSetSessionPreset(session.sessionPreset))
    }

    @MainActor
    func testStartBeforeConfigureDoesNotRunTheSession() async {
        let model = CameraModel()
        model.start()
        _ = await model.isUsingTrustedCamera()   // drain the session queue
        await Task.yield()
        XCTAssertFalse(model.session.isRunning)
        XCTAssertFalse(model.isRunning)
        model.stop()
    }

    @MainActor
    func testSwitchCameraBeforeConfigureOnlyChoosesPosition() async {
        let model = CameraModel()
        model.switchCamera()
        XCTAssertEqual(model.position, .front)
        _ = await model.isUsingTrustedCamera()
        XCTAssertTrue(model.session.inputs.isEmpty)
        XCTAssertNil(model.error)
    }

    @MainActor
    func testDeviceControlsAreSafeWithoutDevice() async {
        let model = CameraModel()
        model.setZoom(2)
        model.setZoom(.nan)
        model.setZoom(magnification: 1.5, stayOnWideLens: true)
        model.pinActiveLens()
        model.unpinActiveLens()
        model.setTorch(true)
        model.focus(atViewPoint: CGPoint(x: 10, y: 10))
        model.focus(atViewPoint: CGPoint(x: 10, y: 10), resetAfter: nil)
        _ = await model.isUsingTrustedCamera()
        await Task.yield()
        XCTAssertFalse(model.isTorchOn)
        XCTAssertEqual(model.zoomFactor, 1)
        XCTAssertEqual(model.zoomMagnification, 1)
        XCTAssertEqual(model.zoomLayout, CameraZoomLayout())
    }
}

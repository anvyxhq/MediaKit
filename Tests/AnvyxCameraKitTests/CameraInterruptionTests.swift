//
//  CameraInterruptionTests.swift
//  CameraKit
//
//  Created by AnhPT on 10/07/2026.
//

import XCTest
import AVFoundation
@testable import AnvyxCameraKit

final class CameraInterruptionTests: XCTestCase {
    @MainActor
    func testInterruptionStateTracksNotifications() {
        let model = CameraModel()
        XCTAssertFalse(model.isInterrupted)
        XCTAssertNil(model.interruptionReason)

        let begin = Notification(
            name: AVCaptureSession.wasInterruptedNotification,
            object: model.session,
            userInfo: [AVCaptureSessionInterruptionReasonKey:
                        NSNumber(value: AVCaptureSession.InterruptionReason.audioDeviceInUseByAnotherClient.rawValue)]
        )
        model.beginInterruption(begin)
        XCTAssertTrue(model.isInterrupted)
        XCTAssertEqual(model.interruptionReason, .audioDeviceInUseByAnotherClient)

        let end = Notification(name: AVCaptureSession.interruptionEndedNotification, object: model.session)
        model.endInterruption(end)
        XCTAssertFalse(model.isInterrupted)
        XCTAssertNil(model.interruptionReason)
    }

    @MainActor
    func testNotificationsForOtherSessionsAreIgnored() {
        let model = CameraModel()
        let otherSession = AVCaptureSession()
        let begin = Notification(name: AVCaptureSession.wasInterruptedNotification, object: otherSession)
        model.beginInterruption(begin)
        XCTAssertFalse(model.isInterrupted) // not our session
    }
}

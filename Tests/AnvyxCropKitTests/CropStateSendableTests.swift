//
//  CropStateSendableTests.swift
//  CropKit
//
//  Created by AnhPT on 10/07/2026.
//

import XCTest
@testable import AnvyxCropKit

/// Compile-time requirement: fails to build if `T` is not `Sendable`.
private func requireSendable<T: Sendable>(_ value: T) -> T { value }

@MainActor
final class CropStateSendableTests: XCTestCase {

    func testCropStateConformsToSendable() {
        let state = CropState(
            normalizedBox: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6),
            zoomScale: 2, normalizedOffset: CGPoint(x: 0.1, y: 0.1), rotationAngle: .pi / 4)
        _ = requireSendable(state)
        _ = requireSendable(ImageAdjustments.none)
        _ = requireSendable(ColorFilter.none)
        _ = requireSendable(CropInfo(cropSize: CGSize(width: 10, height: 10),
                                     imageViewSize: CGSize(width: 20, height: 20)))
    }

    func testCropDocumentIsSendable() {
        let doc = CropDocument(workingImage: UIImage())
        _ = requireSendable(doc)
    }

    func testCropStateCodableRoundTrip() throws {
        let state = CropState(
            normalizedBox: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6),
            zoomScale: 2, normalizedOffset: CGPoint(x: 0.3, y: 0.4), rotationAngle: 1.2)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CropState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testCropStateCrossesActorBoundary() async {
        let state = CropState(zoomScale: 3)
        let echoed = await Task.detached { state }.value   // requires Sendable to capture
        XCTAssertEqual(echoed, state)
    }
}

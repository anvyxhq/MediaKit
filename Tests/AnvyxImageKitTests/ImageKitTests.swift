//
//  ImageKitTests.swift
//  ImageKit
//
//  Created by AnhPT on 03/07/2026.
//

import XCTest
@testable import ImageKit

final class ImageKitTests: XCTestCase {

    func testSolidColorImageHasRequestedSize() {
        let image = UIImage.solid(.red, size: CGSize(width: 4, height: 4))
        XCTAssertEqual(image.size, CGSize(width: 4, height: 4))
    }

    func testCropClampsToBounds() {
        let image = UIImage.solid(.green, size: CGSize(width: 10, height: 10))
        // Request a crop partly outside bounds; should clamp, not crash.
        let cropped = image.cropped(to: CGRect(x: 5, y: 5, width: 100, height: 100))
        XCTAssertNotNil(cropped)
    }

    func testRoundTripUIImageToPixelBufferAndBack() {
        let image = UIImage.solid(.blue, size: CGSize(width: 8, height: 8))
        guard let buffer = image.toCVPixelBuffer() else {
            return XCTFail("expected a pixel buffer")
        }
        XCTAssertEqual(buffer.pixelWidth, 8)
        XCTAssertEqual(buffer.pixelHeight, 8)
        XCTAssertNotNil(buffer.toUIImage())
    }
}

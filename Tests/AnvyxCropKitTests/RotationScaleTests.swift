//
//  RotationScaleTests.swift
//  CropKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import UIKit
@testable import AnvyxCropKit

final class RotationScaleTests: XCTestCase {

    /// A @3x image whose pixel dimensions are known.
    private func scaledImage(width: CGFloat, height: CGFloat, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testRotate90PreservesPixelDimensions() {
        let image = scaledImage(width: 100, height: 60, scale: 3)
        XCTAssertEqual(image.cgImage?.width, 300)   // 100pt × 3
        XCTAssertEqual(image.cgImage?.height, 180)  // 60pt × 3

        let rotated = ImageCropper.rotated90(image, quarterTurns: 1)!
        XCTAssertEqual(rotated.scale, 3)
        // Dimensions swap, pixel count stays the same — must NOT be multiplied by scale.
        XCTAssertEqual(rotated.cgImage?.width, 180)
        XCTAssertEqual(rotated.cgImage?.height, 300)
    }

    func testRepeatedRotate90DoesNotGrow() {
        // The runaway-freeze regression: each rotate must not inflate the image.
        var image = scaledImage(width: 100, height: 60, scale: 3)
        for _ in 0..<6 { image = ImageCropper.rotated90(image, quarterTurns: 1)! }
        // 6 quarter turns = full 1.5 turns → even count of swaps → back to 300×180.
        XCTAssertEqual(image.cgImage?.width, 300)
        XCTAssertEqual(image.cgImage?.height, 180)
    }

    func testFlipPreservesPixelDimensions() {
        let image = scaledImage(width: 100, height: 60, scale: 3)
        let flipped = ImageCropper.flipped(image, horizontally: true, vertically: false)!
        XCTAssertEqual(flipped.scale, 3)
        XCTAssertEqual(flipped.cgImage?.width, 300)
        XCTAssertEqual(flipped.cgImage?.height, 180)
    }
}

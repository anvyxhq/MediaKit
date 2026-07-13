//
//  ImageAdjustTests.swift
//  CropKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import UIKit
@testable import AnvyxCropKit

final class ImageAdjustTests: XCTestCase {

    private func image() -> UIImage {
        let size = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.6, green: 0.4, blue: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func firstPixel(_ image: UIImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return px
    }

    func testDefaultsAreIdentity() {
        XCTAssertTrue(ImageAdjustments().isIdentity)
        XCTAssertTrue(ImageAdjustments.none.isIdentity)
    }

    func testNewKnobsBreakIdentity() {
        XCTAssertFalse(ImageAdjustments(temperature: 5000).isIdentity)
        XCTAssertFalse(ImageAdjustments(tint: 12).isIdentity)
        XCTAssertFalse(ImageAdjustments(vibrance: 0.4).isIdentity)
    }

    func testIdentityIsPassthrough() {
        let src = image()
        XCTAssertTrue(ImageCropper.adjusted(src, .none) === src)
    }

    func testTemperatureChangesPixels() {
        let src = image()
        let warmed = ImageCropper.adjusted(src, ImageAdjustments(temperature: 4000))
        XCTAssertNotEqual(firstPixel(warmed), firstPixel(src))
    }

    func testTintChangesPixels() {
        let src = image()
        let tinted = ImageCropper.adjusted(src, ImageAdjustments(tint: 30))
        XCTAssertNotEqual(firstPixel(tinted), firstPixel(src))
    }

    func testVibranceChangesPixels() {
        let src = image()
        let punchy = ImageCropper.adjusted(src, ImageAdjustments(vibrance: 0.8))
        XCTAssertNotEqual(firstPixel(punchy), firstPixel(src))
    }

    func testAdjustmentPreservesSize() {
        let src = image()
        let out = ImageCropper.adjusted(src, ImageAdjustments(temperature: 4000, tint: 20, vibrance: 0.5))
        XCTAssertEqual(out.size, src.size)
    }
}

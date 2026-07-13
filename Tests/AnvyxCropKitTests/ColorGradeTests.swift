//
//  ColorGradeTests.swift
//  CropKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import UIKit
@testable import AnvyxCropKit

final class ColorGradeTests: XCTestCase {

    private func image() -> CGImage {
        let size = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.6, green: 0.4, blue: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }.cgImage!
    }

    /// First pixel's RGBA — cheap way to tell grades apart.
    private func firstPixel(_ cg: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return px
    }

    func testOriginalIsPassthrough() {
        let src = image()
        XCTAssertTrue(ColorGradePreset.original.apply(to: src) === src)
    }

    func testEveryPresetKeepsSizeAndProducesImage() {
        let src = image()
        let context = CIContext(options: nil)
        for preset in ColorGradePreset.allCases {
            let out = preset.apply(to: src, context: context)
            XCTAssertEqual(out.width, src.width, "\(preset) changed width")
            XCTAssertEqual(out.height, src.height, "\(preset) changed height")
        }
    }

    func testPresetsActuallyChangePixels() {
        let src = image()
        let base = firstPixel(src)
        // A few distinctive looks must differ from the source.
        for preset in [ColorGradePreset.vivid, .filmNoir, .cyberpunk, .warm] {
            XCTAssertNotEqual(firstPixel(preset.apply(to: src)), base, "\(preset) had no visible effect")
        }
    }

    func testNoirIsGrayscale() {
        let px = firstPixel(ColorGradePreset.filmNoir.apply(to: image()))
        // R≈G≈B for a desaturated look.
        XCTAssertLessThanOrEqual(abs(Int(px[0]) - Int(px[1])), 6)
        XCTAssertLessThanOrEqual(abs(Int(px[1]) - Int(px[2])), 6)
    }
}

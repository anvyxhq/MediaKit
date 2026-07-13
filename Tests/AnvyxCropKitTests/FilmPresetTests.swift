//
//  FilmPresetTests.swift
//  CropKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import UIKit
@testable import AnvyxCropKit

final class FilmPresetTests: XCTestCase {

    private func image() -> CGImage {
        let size = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.6, green: 0.4, blue: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }.cgImage!
    }

    private func firstPixel(_ cg: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return px
    }

    func testCatalogSize() {
        XCTAssertEqual(FilmPreset.allCases.count, 41)
    }

    func testEveryPresetKeepsSizeAndHasName() {
        let src = image()
        let context = CIContext(options: nil)
        for preset in FilmPreset.allCases {
            let out = preset.apply(to: src, context: context)
            XCTAssertEqual(out.width, src.width, "\(preset) changed width")
            XCTAssertEqual(out.height, src.height, "\(preset) changed height")
            XCTAssertFalse(preset.displayName.isEmpty, "\(preset) has no display name")
        }
    }

    func testEveryPresetChangesPixels() {
        let src = image()
        let base = firstPixel(src)
        let context = CIContext(options: nil)
        for preset in FilmPreset.allCases {
            XCTAssertNotEqual(firstPixel(preset.apply(to: src, context: context)), base,
                              "\(preset) had no visible effect")
        }
    }

    func testInkwellRecipeIsGrayscale() {
        // inkwell has no overlay, so the recipe-only output is desaturated.
        let px = firstPixel(FilmPreset.inkwell.recipe.apply(to: image()))
        XCTAssertLessThanOrEqual(abs(Int(px[0]) - Int(px[1])), 6)
        XCTAssertLessThanOrEqual(abs(Int(px[1]) - Int(px[2])), 6)
    }

    func testOverlayChangesResultVsRecipeOnly() {
        let src = image()
        let context = CIContext(options: nil)
        // Presets with an overlay should differ from their overlay-free recipe.
        for preset in [FilmPreset.walden, .toaster, .clarendon, .xpro2] {
            XCTAssertFalse(preset.overlays.isEmpty, "\(preset) expected an overlay")
            let full = firstPixel(preset.apply(to: src, context: context))
            let recipeOnly = firstPixel(preset.recipe.apply(to: src, context: context))
            XCTAssertNotEqual(full, recipeOnly, "\(preset) overlay had no effect")
        }
    }

    func testIntensityZeroRecipeIsPassthrough() {
        let src = image()
        // Recipe-only, no overlays → intensity 0 is a no-op.
        XCTAssertTrue(FilmPreset.clarendon.recipe.apply(to: src, intensity: 0) === src)
    }

    func testHalfIntensityDiffersFromFull() {
        let src = image()
        let context = CIContext(options: nil)
        let full = firstPixel(FilmPreset.lofi.recipe.apply(to: src, intensity: 1, context: context))
        let half = firstPixel(FilmPreset.lofi.recipe.apply(to: src, intensity: 0.5, context: context))
        XCTAssertNotEqual(half, firstPixel(src))
        XCTAssertNotEqual(half, full)
    }

    func testRecipeScaledToZeroIsNeutral() {
        XCTAssertTrue(FilmPreset.nashville.recipe.scaled(by: 0).isNeutral)
    }

    func testPresetIntensityZeroIsPassthrough() {
        // With overlays scaled too, intensity 0 must be a full no-op even for
        // overlay-carrying presets.
        let src = image()
        XCTAssertTrue(FilmPreset.walden.apply(to: src, intensity: 0) === src)
    }

    func testPresetIntensityHalfDiffersFromFull() {
        let src = image()
        let context = CIContext(options: nil)
        let full = firstPixel(FilmPreset.walden.apply(to: src, intensity: 1, context: context))
        let half = firstPixel(FilmPreset.walden.apply(to: src, intensity: 0.5, context: context))
        XCTAssertNotEqual(half, firstPixel(src))
        XCTAssertNotEqual(half, full)
    }

    func testProcessFilmIntensityZeroSkipsPreset() {
        let src = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let out = ImageCropper.process(src, adjustments: .none, filter: .none,
                                       film: .clarendon, filmIntensity: 0)
        XCTAssertTrue(out === src)
    }
}

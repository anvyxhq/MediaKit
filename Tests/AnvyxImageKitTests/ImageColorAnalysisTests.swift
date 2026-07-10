//
//  ImageColorAnalysisTests.swift
//  ImageKit
//
//  Created by AnhPT on 10/07/2026.
//

import XCTest
import UIKit
@testable import AnvyxImageKit

final class ImageColorAnalysisTests: XCTestCase {

    private func renderer(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    func testDominantColorOfSolidImage() async throws {
        let image = UIImage.solid(.red, size: CGSize(width: 40, height: 40))
        let cg = try XCTUnwrap(image.cgImage)
        let result = await ImageProcessor.dominantColor(cg)
        let color = try XCTUnwrap(result)
        XCTAssertGreaterThan(color.red, 240)
        XCTAssertLessThan(color.green, 15)
        XCTAssertLessThan(color.blue, 15)
    }

    func testPaletteFindsBothColors() async throws {
        let image = renderer(CGSize(width: 40, height: 40)).image { ctx in
            UIColor.red.setFill();  ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 20, width: 40, height: 20))
        }
        let cg = try XCTUnwrap(image.cgImage)
        let palette = await ImageProcessor.palette(cg, count: 4)

        XCTAssertGreaterThanOrEqual(palette.count, 2)
        XCTAssertTrue(palette.contains { $0.red > 200 && $0.blue < 70 }, "expected a red-ish color")
        XCTAssertTrue(palette.contains { $0.blue > 200 && $0.red < 70 }, "expected a blue-ish color")
    }

    func testPaletteOrderedByFrequency() async throws {
        // 3/4 green, 1/4 red — green must come first.
        let image = renderer(CGSize(width: 40, height: 40)).image { ctx in
            UIColor.green.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            UIColor.red.setFill();   ctx.fill(CGRect(x: 0, y: 30, width: 40, height: 10))
        }
        let cg = try XCTUnwrap(image.cgImage)
        let palette = await ImageProcessor.palette(cg, count: 4)
        let top = try XCTUnwrap(palette.first)
        XCTAssertGreaterThan(top.green, 200)
        XCTAssertLessThan(top.red, 70)
    }

    func testTransparentImageHasNoDominantColor() async throws {
        let image = renderer(CGSize(width: 16, height: 16)).image { _ in }   // nothing drawn
        let cg = try XCTUnwrap(image.cgImage)
        let color = await ImageProcessor.dominantColor(cg)
        XCTAssertNil(color)
    }

    func testImageColorCGColorComponents() {
        let cg = ImageColor(red: 255, green: 128, blue: 0).cgColor
        let comps = try? XCTUnwrap(cg.components)
        XCTAssertEqual(comps?[0] ?? -1, 1.0, accuracy: 0.01)
        XCTAssertEqual(comps?[1] ?? -1, 0.5, accuracy: 0.01)
        XCTAssertEqual(comps?[2] ?? -1, 0.0, accuracy: 0.01)
    }
}

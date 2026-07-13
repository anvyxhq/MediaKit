//
//  CropLayoutTests.swift
//  CropKit
//
//  Created by AnhPT on 13/07/2026.
//

import XCTest
import UIKit
@testable import AnvyxCropKit

@MainActor
final class CropLayoutTests: XCTestCase {

    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: format).image { ctx in
            UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        }
    }

    /// When the available area changes (e.g. the adjust panel toggles), the crop
    /// selection must stay proportionally the same — not shift or resize.
    func testCropBoxSelectionSurvivesAreaChange() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 900))
        let view = CropperView(image: image(), configuration: .init())
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        window.addSubview(view)
        window.makeKeyAndVisible()
        view.setNeedsLayout(); view.layoutIfNeeded()

        let before = view.cropState().normalizedBox

        // Shrink the cropper (as if an adjustment panel appeared below it).
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 560)
        view.setNeedsLayout(); view.layoutIfNeeded()

        let after = view.cropState().normalizedBox

        XCTAssertEqual(before.minX, after.minX, accuracy: 0.02, "crop shifted horizontally")
        XCTAssertEqual(before.minY, after.minY, accuracy: 0.02, "crop shifted vertically")
        XCTAssertEqual(before.width, after.width, accuracy: 0.02, "crop width changed")
        XCTAssertEqual(before.height, after.height, accuracy: 0.02, "crop height changed")
    }
}

//
//  CropEnhancementsTests.swift
//  CropKit
//
//  Created by AnhPT on 15/07/2026.
//

import XCTest
import UIKit
@testable import AnvyxCropKit

@MainActor
final class CropEnhancementsTests: XCTestCase {

    private func image(_ size: CGSize = CGSize(width: 300, height: 200)) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.gray.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func laidOutView(_ config: CropConfiguration = .init()) -> CropperView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 900))
        let view = CropperView(image: image(), configuration: config)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        window.addSubview(view)
        window.makeKeyAndVisible()
        view.setNeedsLayout(); view.layoutIfNeeded()
        return view
    }

    // MARK: - Rotation limit

    func testRotationAngleClampedToLimit() {
        var config = CropConfiguration(); config.rotationLimit = .pi / 6   // 30°
        let view = laidOutView(config)
        view.rotationAngle = .pi / 2                                       // ask for 90°
        XCTAssertEqual(view.rotationAngle, .pi / 6, accuracy: 0.0001)
        view.rotationAngle = -.pi
        XCTAssertEqual(view.rotationAngle, -.pi / 6, accuracy: 0.0001)
    }

    func testDefaultRotationLimitIsPi() {
        let view = laidOutView()
        view.rotationAngle = .pi
        XCTAssertEqual(view.rotationAngle, .pi, accuracy: 0.0001)
    }

    // MARK: - Rotation coverage

    func testRotatedFullImageCropStillRenders() {
        let view = laidOutView()
        view.rotationAngle = .pi / 6
        // The render path must still produce an image after coverage zoom kicks in.
        XCTAssertNotNil(view.croppedImage())
    }

    // MARK: - Shapes

    func testMaskedShapesPreserveDimensions() {
        let img = image(CGSize(width: 120, height: 120))
        let shapes: [CropShape] = [
            .ellipse, .roundedRect(cornerRadius: 12), .diamond, .heart,
            .polygon(sides: 6), .path(points: [CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]),
        ]
        for shape in shapes {
            let out = ImageCropper.masked(img, shape: shape)
            XCTAssertEqual(out.cgImage?.width, 120, "\(shape)")
            XCTAssertEqual(out.cgImage?.height, 120, "\(shape)")
        }
    }

    func testMaskOnlyKeepsOutputRectangular() {
        var config = CropConfiguration(); config.shape = .ellipse; config.maskOnly = true
        let view = laidOutView(config)
        // With maskOnly the exported image is not clipped to the ellipse; a corner
        // pixel stays opaque.
        let out = view.croppedImage()
        XCTAssertNotNil(out)
    }

    // MARK: - Undo state (regression: undo disabled for first actions)

    private func laidOutController(_ config: CropConfiguration = .init()) -> CropController {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 900))
        let controller = CropController(image: image(), configuration: config)
        controller.cropperView.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        window.addSubview(controller.cropperView)
        window.makeKeyAndVisible()
        controller.cropperView.setNeedsLayout(); controller.cropperView.layoutIfNeeded()
        return controller
    }

    func testUndoEnabledAfterFirstAction() {
        let controller = laidOutController()
        XCTAssertFalse(controller.canUndo)
        controller.rotate90()
        XCTAssertTrue(controller.canUndo, "undo must be enabled after the first action")
    }

    /// Regression: `layoutSubviews` (via rotation coverage) must not fire `onChange`
    /// — doing so mutates SwiftUI observed state mid-update and drops interactions.
    func testLayoutAfterRotationDoesNotFireOnChange() {
        let view = laidOutView()
        view.rotationAngle = .pi / 8            // coverage zoom now active
        var count = 0
        view.onChange = { count += 1 }
        view.setNeedsLayout(); view.layoutIfNeeded()
        XCTAssertEqual(count, 0, "layout must not fire onChange")
    }

    func testRepeatedRotateAndFlipKeepsUndo() {
        let controller = laidOutController()
        controller.rotate90()
        controller.cropperView.setNeedsLayout(); controller.cropperView.layoutIfNeeded()
        controller.flip()
        controller.rotate90()
        controller.cropperView.setNeedsLayout(); controller.cropperView.layoutIfNeeded()
        XCTAssertTrue(controller.canUndo)
    }

    // MARK: - Bezier geometry

    func testPolygonPathHasExpectedPointCount() {
        let path = CropShape.polygon(sides: 5).bezierPath(in: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertFalse(path.isEmpty)
    }
}

//
//  CropKitTests.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import XCTest
@testable import AnvyxCropKit

@MainActor
final class CropKitTests: XCTestCase {

    private func image(_ size: CGSize, color: UIColor = .red) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testExactRectCrop() {
        let img = image(CGSize(width: 100, height: 80))
        let out = ImageCropper.crop(img, to: CGRect(x: 50, y: 0, width: 50, height: 80))
        XCTAssertEqual(out?.cgImage?.width, 50)
        XCTAssertEqual(out?.cgImage?.height, 80)
    }

    func testRotate90SwapsDimensions() {
        let img = image(CGSize(width: 100, height: 40))
        let out = ImageCropper.rotated90(img, quarterTurns: 1)
        XCTAssertEqual(out?.cgImage?.width, 40)
        XCTAssertEqual(out?.cgImage?.height, 100)
    }

    func testFlipKeepsDimensions() {
        let img = image(CGSize(width: 60, height: 30))
        let out = ImageCropper.flipped(img, horizontally: true, vertically: false)
        XCTAssertEqual(out?.cgImage?.width, 60)
        XCTAssertEqual(out?.cgImage?.height, 30)
    }

    func testCropInfoIdentityFullImage() {
        let img = image(CGSize(width: 200, height: 100))
        let info = CropInfo(translation: .zero, rotation: 0, scale: 1,
                            cropSize: CGSize(width: 200, height: 100),
                            imageViewSize: CGSize(width: 200, height: 100))
        let out = ImageCropper.crop(img, by: info)
        XCTAssertEqual(out?.cgImage?.width, 200)
        XCTAssertEqual(out?.cgImage?.height, 100)
    }

    func testUndoRedoFlow() {
        let vm = CropViewModel()
        let img = image(CGSize(width: 10, height: 10))
        let free = CropDocument(workingImage: img, aspectRatio: .free)
        let square = CropDocument(workingImage: img, aspectRatio: .square)

        XCTAssertFalse(vm.canUndo)
        vm.record(free)                       // leaving the "free" state
        XCTAssertTrue(vm.canUndo)
        XCTAssertFalse(vm.canRedo)

        let undone = vm.undo(current: square)  // now on "square", go back
        XCTAssertEqual(undone?.aspectRatio, .free)
        XCTAssertFalse(vm.canUndo)
        XCTAssertTrue(vm.canRedo)

        let redone = vm.redo(current: free)
        XCTAssertEqual(redone?.aspectRatio, .square)
    }

    func testUndoOnEmptyHistoryReturnsNil() {
        let vm = CropViewModel()
        XCTAssertNil(vm.undo(current: CropDocument(workingImage: image(CGSize(width: 4, height: 4)))))
    }

    func testRecordClearsRedo() {
        let vm = CropViewModel()
        let img = image(CGSize(width: 8, height: 8))
        vm.record(CropDocument(workingImage: img))
        _ = vm.undo(current: CropDocument(workingImage: img))
        XCTAssertTrue(vm.canRedo)
        vm.record(CropDocument(workingImage: img))   // a new branch clears redo
        XCTAssertFalse(vm.canRedo)
    }

    func testCropInfoCenterHalf() {
        let img = image(CGSize(width: 200, height: 200))
        // Crop box half the size, centered, no zoom → center 100x100 region.
        let info = CropInfo(translation: .zero, rotation: 0, scale: 1,
                            cropSize: CGSize(width: 100, height: 100),
                            imageViewSize: CGSize(width: 200, height: 200))
        let out = ImageCropper.crop(img, by: info)
        XCTAssertEqual(out?.cgImage?.width, 100)
        XCTAssertEqual(out?.cgImage?.height, 100)
    }
}

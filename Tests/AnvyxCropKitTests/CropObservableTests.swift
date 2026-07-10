//
//  CropObservableTests.swift
//  CropKit
//
//  Created by AnhPT on 10/07/2026.
//

import XCTest
import Observation
@testable import AnvyxCropKit

/// A tiny reference box: `withObservationTracking`'s `onChange` is `@Sendable`,
/// so it can't mutate a captured local `var`.
private final class Flag: @unchecked Sendable { var raised = false }

@MainActor
final class CropObservableTests: XCTestCase {

    func testViewModelUndoStateIsObservable() {
        let viewModel = CropViewModel()
        let flag = Flag()
        withObservationTracking {
            _ = viewModel.canUndo
        } onChange: {
            flag.raised = true
        }

        viewModel.record(CropDocument(workingImage: UIImage()))   // flips canUndo true

        XCTAssertTrue(flag.raised, "@Observable should notify on canUndo change")
        XCTAssertTrue(viewModel.canUndo)
    }

    func testUndoRedoRoundTripThroughViewModel() {
        let viewModel = CropViewModel()
        let a = CropDocument(workingImage: UIImage())
        let b = CropDocument(workingImage: UIImage())

        viewModel.record(a)
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertEqual(viewModel.undo(current: b)?.crop, a.crop)
        XCTAssertTrue(viewModel.canRedo)
        XCTAssertEqual(viewModel.redo(current: a)?.crop, b.crop)
    }
}

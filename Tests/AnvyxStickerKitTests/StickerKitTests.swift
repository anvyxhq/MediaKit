//
//  StickerKitTests.swift
//  StickerKit
//
//  Created by AnhPT on 03/07/2026.
//

import XCTest
@testable import StickerKit

@MainActor
final class StickerKitTests: XCTestCase {

    func testAddSelectRemove() {
        let canvas = StickerCanvasView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let text = TextItemView(text: "Hi", frame: CGRect(x: 0, y: 0, width: 120, height: 40))
        canvas.add(text, at: CGPoint(x: 150, y: 150))
        XCTAssertEqual(canvas.items.count, 1)
        XCTAssertTrue(text.isSelected)

        canvas.deselectAll()
        XCTAssertNil(canvas.selectedItem)

        canvas.remove(text)
        XCTAssertEqual(canvas.items.count, 0)
    }

    func testSnapshotRestoreRoundTrip() {
        let canvas = StickerCanvasView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let img = UIImageView().image ?? UIImage()
        let item = ImageItemView(id: "sig", image: img, frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        canvas.add(item, at: CGPoint(x: 100, y: 100))

        let snap = canvas.snapshot()
        XCTAssertEqual(snap.first?.id, "sig")

        // Codable round-trip
        let data = try! JSONEncoder().encode(snap)
        let decoded = try! JSONDecoder().decode([TransformState].self, from: data)
        item.apply(decoded[0])
        XCTAssertEqual(item.center, CGPoint(x: 100, y: 100))
    }

    func testUndoHistoryGeneric() {
        let history = UndoHistory<Int>()
        XCTAssertFalse(history.canUndo)
        history.record(1)
        XCTAssertTrue(history.canUndo)
        XCTAssertEqual(history.undo(current: 2), 1)
        XCTAssertTrue(history.canRedo)
        XCTAssertEqual(history.redo(current: 1), 2)
        // A fresh record clears redo.
        history.record(5)
        XCTAssertFalse(history.canRedo)
    }

    func testCanvasUndoRestoresRemovedItem() {
        let canvas = StickerCanvasView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        canvas.add(TextItemView(text: "A", frame: CGRect(x: 0, y: 0, width: 80, height: 40)), at: CGPoint(x: 100, y: 100))
        canvas.add(TextItemView(text: "B", frame: CGRect(x: 0, y: 0, width: 80, height: 40)), at: CGPoint(x: 200, y: 200))
        XCTAssertEqual(canvas.items.count, 2)

        canvas.remove(canvas.items[0])
        XCTAssertEqual(canvas.items.count, 1)

        canvas.undo()
        XCTAssertEqual(canvas.items.count, 2)      // rebuilt from history
        XCTAssertTrue(canvas.canRedo)

        canvas.redo()
        XCTAssertEqual(canvas.items.count, 1)
    }

    func testFlattenProducesImage() {
        let canvas = StickerCanvasView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        canvas.add(TextItemView(text: "X", frame: CGRect(x: 0, y: 0, width: 40, height: 20)))
        let image = canvas.flattenedImage()
        XCTAssertEqual(image.size, CGSize(width: 100, height: 100))
    }
}

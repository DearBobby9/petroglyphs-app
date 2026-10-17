import XCTest
import PencilKit

final class CanvasDocumentTests: XCTestCase {
    @MainActor
    func testClearRemovesInkSynchronously() {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        model.drawing = makeDrawing()
        model.clear()
        XCTAssertTrue(model.drawing.strokes.isEmpty, "The clear operation must finish before new Pencil input is accepted.")
    }

    @MainActor
    func testClearThenDrawUndoAndRedoFollowEditOrder() throws {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        model.drawing = makeDrawing()
        let original = model.drawing
        model.clear()
        model.drawing = makeDrawing(ink: .blue)
        model.undo()
        XCTAssertTrue(model.drawing.strokes.isEmpty, "Undo the new stroke before undoing clear.")
        model.undo()
        XCTAssertEqual(model.drawing.strokes.first?.ink.color, original.strokes.first?.ink.color)
        XCTAssertEqual(model.drawing.strokes.first?.path.map(\.location), original.strokes.first?.path.map(\.location))
        model.redo()
        XCTAssertTrue(model.drawing.strokes.isEmpty)
        model.redo()
        XCTAssertEqual(model.drawing.strokes.first?.ink.color, UIColor.blue)
        model.undo()
        model.drawing = makeDrawing(ink: .red)
        XCTAssertFalse(model.canRedo, "Editing after undo must discard the replaced redo branch.")
    }

    @MainActor
    func testToolUpdatesAndFinalCallbackShareOneUndoBoundary() {
        let storage = temporaryStorage()
        let model = CanvasViewModel(storageURL: storage)
        let firstGesture = UUID()
        model.updateDrawing(makeDrawing(), gestureID: firstGesture, saveImmediately: false)
        model.save()
        let completed = PKDrawing(strokes: makeDrawing().strokes + makeDrawing(ink: .blue).strokes)
        model.updateDrawing(completed, gestureID: firstGesture)
        let secondGesture = UUID()
        model.updateDrawing(PKDrawing(strokes: completed.strokes + makeDrawing(ink: .red).strokes), gestureID: secondGesture)
        model.undo()
        XCTAssertEqual(model.drawing.strokes.count, 2)
        model.undo()
        XCTAssertTrue(model.drawing.strokes.isEmpty)
        XCTAssertFalse(model.canUndo)
        model.redo()
        XCTAssertEqual(model.drawing.strokes.count, 2)
        let restored = CanvasViewModel(storageURL: storage)
        XCTAssertEqual(restored.drawing.strokes.count, 2)
        XCTAssertFalse(restored.canUndo, "Only the latest drawing is persisted; undo history lasts for this app session.")
        XCTAssertFalse(restored.canRedo)
    }

    @MainActor
    func testNewModelRestoresEditableDrawing() throws {
        let storage = temporaryStorage()
        let original = CanvasViewModel(storageURL: storage)
        original.drawing = makeDrawing()
        original.background = .charcoal
        let restored = CanvasViewModel(storageURL: storage)
        XCTAssertEqual(restored.drawing.strokes.count, 1, "Recreating the canvas must restore its native drawing.")
        let restoredStroke = try XCTUnwrap(restored.drawing.strokes.first)
        let originalStroke = try XCTUnwrap(original.drawing.strokes.first)
        XCTAssertEqual(restoredStroke.ink.inkType, originalStroke.ink.inkType)
        XCTAssertEqual(restoredStroke.ink.color, originalStroke.ink.color)
        XCTAssertEqual(restoredStroke.path.map(\.location), originalStroke.path.map(\.location))
        XCTAssertEqual(restoredStroke.path.map(\.force), originalStroke.path.map(\.force))
        XCTAssertEqual(restoredStroke.path.map(\.size), originalStroke.path.map(\.size))
        XCTAssertEqual(restored.snapshot(), original.snapshot())
        XCTAssertEqual(restored.documentID, original.documentID)
        XCTAssertEqual(restored.revision, original.revision)
        XCTAssertEqual(restored.background, .charcoal)
        XCTAssertEqual(restored.exportBounds, original.exportBounds)
        restored.drawing = PKDrawing(strokes: restored.drawing.strokes + makeDrawing().strokes)
        XCTAssertEqual(CanvasViewModel(storageURL: storage).drawing.strokes.count, 2)
    }

    @MainActor
    func testFirstDocumentMigratesActualBackgroundAndIgnoresLaterThemeChanges() throws {
        let suite = "CanvasDocumentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "darkModeEnabled")
        defaults.set("3A5678", forKey: "darkCanvasBackgroundHex")
        defaults.set("FFFFFF", forKey: "canvasBackgroundHex")
        let storage = temporaryStorage()
        let original = CanvasViewModel(storageURL: storage, defaults: defaults)
        XCTAssertEqual(original.background.rawValue, "3A5678")
        defaults.set(false, forKey: "darkModeEnabled")
        defaults.set("000000", forKey: "darkCanvasBackgroundHex")
        let restored = CanvasViewModel(storageURL: storage, defaults: defaults)
        XCTAssertEqual(restored.background, original.background)
        XCTAssertEqual(restored.documentID, original.documentID)
    }

    @MainActor
    func testSnapshotUsesSavedDocumentBackgroundAndRevision() throws {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        model.drawing = makeDrawing()
        model.background = .white
        let first = try XCTUnwrap(model.snapshot())
        let firstName = model.snapshotFilename
        model.background = .black
        let second = try XCTUnwrap(model.snapshot())
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(firstName, model.snapshotFilename)
        let restored = try JSONDecoder().decode(CanvasDocument.self, from: JSONEncoder().encode(CanvasDocument(background: .white)))
        let exported = try CanvasExporter().export(document: restored, duration: 0)
        XCTAssertEqual(UIImage(data: try XCTUnwrap(Data(base64Encoded: exported.imageBase64)))?.size, CanvasDocument.emptyBounds.size)
    }

    @MainActor
    func testUnreadableAndUnknownVersionDocumentsRemainUntouched() throws {
        var valid = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(CanvasDocument(background: .white))) as? [String: Any])
        valid["version"] = 999
        let unsupported = try JSONSerialization.data(withJSONObject: valid)
        for original in [Data("{broken".utf8), unsupported] {
            let storage = temporaryStorage()
            try original.write(to: storage)
            let model = CanvasViewModel(storageURL: storage)
            XCTAssertNotNil(model.storageError)
            model.drawing = makeDrawing()
            model.background = .black
            XCTAssertFalse(model.save())
            XCTAssertEqual(try Data(contentsOf: storage), original)
        }
    }

    @MainActor
    func testWriteFailureIsVisibleAndCanBeRetried() throws {
        let parent = temporaryStorage()
        try Data("blocks-directory".utf8).write(to: parent)
        let model = CanvasViewModel(storageURL: parent.appending(path: "active.json"))
        model.drawing = makeDrawing()
        XCTAssertNotNil(model.storageError)
        XCTAssertFalse(model.save())
        try FileManager.default.removeItem(at: parent)
        XCTAssertTrue(model.save())
        XCTAssertNil(model.storageError)
        XCTAssertEqual(CanvasViewModel(storageURL: parent.appending(path: "active.json")).drawing.strokes.count, 1)
    }

    private func temporaryStorage() -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CanvasDocumentTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appending(path: "active.json")
    }

    private func makeDrawing(ink: UIColor = .black) -> PKDrawing {
        let points = [20, 40, 60, 80, 100].enumerated().map { index, x in
            PKStrokePoint(location: CGPoint(x: x, y: 40), timeOffset: Double(index) * 0.1,
                          size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_000))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: ink), path: path)])
    }
}

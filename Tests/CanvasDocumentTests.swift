import XCTest
import PencilKit

final class CanvasDocumentTests: XCTestCase {
    @MainActor
    func testCanvasStartsWithRoomToPanInEveryDirectionAndAllowsZoom() {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        let surface = CanvasDocumentSurface(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        surface.apply(model, selecting: false, onSelection: nil)
        surface.layoutIfNeeded()

        XCTAssertLessThan(surface.canvas.minimumZoomScale, 1)
        XCTAssertGreaterThan(surface.canvas.maximumZoomScale, 1)
        XCTAssertGreaterThan(surface.canvas.contentOffset.x, 0, "An empty canvas must allow panning left of the initial document origin.")
        XCTAssertGreaterThan(surface.canvas.contentOffset.y, 0, "An empty canvas must allow panning above the initial document origin.")
        XCTAssertGreaterThan(surface.canvas.contentSize.width - surface.canvas.contentOffset.x, surface.bounds.width)
        XCTAssertGreaterThan(surface.canvas.contentSize.height - surface.canvas.contentOffset.y, surface.bounds.height)
    }

    @MainActor
    func testRepeatedPanRecentringAndZoomPreserveDocumentAndAcceptNegativeCoordinateInk() throws {
        let storage = temporaryStorage()
        let model = CanvasViewModel(storageURL: storage)
        model.drawing = makeDrawing()
        try model.setExportBounds(CGRect(x: -30, y: -40, width: 180, height: 140))
        let revision = model.revision
        let snapshot = model.snapshot()
        let crop = model.selectedExportBounds
        let originalBounds = model.drawing.bounds
        let surface = CanvasDocumentSurface(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        surface.apply(model, selecting: false, onSelection: nil)
        surface.layoutIfNeeded()
        let start = surface.currentViewport.center

        // Move much farther than one backing window, then reverse direction.
        // A fixed-size canvas or an uncompensated rebase would fail this loop.
        for direction: CGFloat in [-1, 1, -1] {
            for _ in 0..<30 {
                let before = surface.currentViewport.center
                surface.canvas.contentOffset.x += 1_200 * direction
                surface.canvas.contentOffset.y += 800 * direction
                surface.viewportDidChange()
                XCTAssertEqual(surface.currentViewport.center.x, before.x + 1_200 * direction, accuracy: 0.001)
                XCTAssertEqual(surface.currentViewport.center.y, before.y + 800 * direction, accuracy: 0.001)
            }
        }
        XCTAssertEqual(surface.currentViewport.center.x, start.x - 36_000, accuracy: 0.001)
        XCTAssertEqual(surface.currentViewport.center.y, start.y - 24_000, accuracy: 0.001)
        let center = surface.currentViewport.center
        model.navigateCanvas(.zoomOut)
        surface.apply(model, selecting: false, onSelection: nil)
        surface.layoutIfNeeded()
        XCTAssertLessThan(surface.canvas.zoomScale, 1)
        let documentPixel = 1 / (surface.canvas.contentScaleFactor * surface.canvas.zoomScale)
        XCTAssertEqual(surface.currentViewport.center.x, center.x, accuracy: documentPixel)
        XCTAssertEqual(surface.currentViewport.center.y, center.y, accuracy: documentPixel)
        surface.saveViewport()
        XCTAssertEqual(model.revision, revision, "Camera movement must not produce a new canvas attachment revision.")
        XCTAssertEqual(model.snapshot(), snapshot)
        XCTAssertEqual(model.selectedExportBounds, crop)
        XCTAssertEqual(surface.documentDrawing(from: surface.canvas.drawing).bounds, originalBounds)

        let coordinator = CanvasView.Coordinator(viewModel: model)
        coordinator.surface = surface
        let localOffset = CGAffineTransform(translationX: surface.canvas.contentOffset.x / surface.canvas.zoomScale,
                                           y: surface.canvas.contentOffset.y / surface.canvas.zoomScale)
        let added = makeDrawing(ink: .blue).transformed(using: localOffset)
        let expected = surface.documentDrawing(from: added).bounds
        surface.canvas.drawing = PKDrawing(strokes: surface.canvas.drawing.strokes + added.strokes)
        coordinator.canvasViewDrawingDidChange(surface.canvas)
        XCTAssertEqual(model.drawing.strokes.count, 2)
        XCTAssertLessThan(expected.maxX, 0)
        XCTAssertLessThan(expected.maxY, 0)
        XCTAssertTrue(model.contentBounds.contains(expected))
        model.undo()
        XCTAssertEqual(model.drawing.bounds, originalBounds)
        model.redo()
        XCTAssertEqual(model.drawing.strokes.count, 2)
        let restored = CanvasViewModel(storageURL: storage)
        XCTAssertEqual(restored.drawing.strokes.count, 2)
        XCTAssertEqual(restored.viewport, model.viewport)
        XCTAssertEqual(restored.selectedExportBounds, crop)
        XCTAssertEqual(restored.snapshot(), model.snapshot())
        let recreated = CanvasDocumentSurface(frame: surface.frame)
        recreated.apply(model, selecting: false, onSelection: nil)
        recreated.layoutIfNeeded()
        XCTAssertEqual(recreated.canvas.zoomScale, surface.canvas.zoomScale, "Recreating UIKit must not replay the last zoom command.")
    }

    @MainActor
    func testReferenceAndExportSelectionStayAlignedWhileZoomingPanningAndResizing() throws {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        try model.setReferenceImage(data: image, name: "Reference.png", sourceID: "test")
        let crop = CGRect(x: -50, y: -20, width: 100, height: 80)
        try model.setExportBounds(crop)
        let surface = CanvasDocumentSurface(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        surface.apply(model, selecting: false, onSelection: nil)
        surface.layoutIfNeeded()
        model.navigateCanvas(.zoomIn)
        surface.apply(model, selecting: false, onSelection: nil)
        surface.layoutIfNeeded()
        surface.canvas.contentOffset.x -= 6_000
        surface.canvas.contentOffset.y -= 4_000
        surface.viewportDidChange()
        let center = surface.currentViewport.center
        surface.frame.size = CGSize(width: 900, height: 500)
        surface.layoutIfNeeded()
        XCTAssertEqual(surface.currentViewport.center.x, center.x, accuracy: 0.001)
        XCTAssertEqual(surface.currentViewport.center.y, center.y, accuracy: 0.001)

        let reference = try XCTUnwrap(surface.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(surface.documentPoint(at: reference.frame.origin).x, 0, accuracy: 0.001)
        XCTAssertEqual(surface.documentPoint(at: reference.frame.origin).y, 0, accuracy: 0.001)
        XCTAssertEqual(reference.frame.width / surface.canvas.zoomScale, 200, accuracy: 0.001)
        XCTAssertEqual(reference.frame.height / surface.canvas.zoomScale, 100, accuracy: 0.001)
        let selection = try XCTUnwrap(surface.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first?.path?.boundingBox)
        XCTAssertEqual(surface.documentPoint(at: selection.origin).x, crop.minX, accuracy: 0.001)
        XCTAssertEqual(surface.documentPoint(at: selection.origin).y, crop.minY, accuracy: 0.001)
        XCTAssertEqual(selection.width / surface.canvas.zoomScale, crop.width, accuracy: 0.001)
        XCTAssertEqual(selection.height / surface.canvas.zoomScale, crop.height, accuracy: 0.001)
    }

    @MainActor
    func testViewportRestoresWithoutChangingContentRevisionAndRejectsInvalidSavedCamera() throws {
        let storage = temporaryStorage()
        let model = CanvasViewModel(storageURL: storage)
        model.drawing = makeDrawing()
        let revision = model.revision
        let viewport = CanvasViewport(center: CGPoint(x: -12_345, y: 67_890), zoom: 0.5)
        model.saveViewport(viewport)
        let restored = CanvasViewModel(storageURL: storage)
        XCTAssertEqual(restored.viewport, viewport)
        XCTAssertEqual(restored.revision, revision)
        let surface = CanvasDocumentSurface(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        surface.apply(restored, selecting: false, onSelection: nil)
        surface.layoutIfNeeded()
        XCTAssertEqual(surface.currentViewport, viewport)

        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: storage)) as? [String: Any])
        var invalid = try XCTUnwrap(encoded["viewport"] as? [String: Any])
        invalid["zoom"] = 0
        encoded["viewport"] = invalid
        let bytes = try JSONSerialization.data(withJSONObject: encoded)
        try bytes.write(to: storage)
        let protected = CanvasViewModel(storageURL: storage)
        XCTAssertNotNil(protected.storageError)
        protected.saveViewport(viewport)
        XCTAssertFalse(protected.save())
        XCTAssertEqual(try Data(contentsOf: storage), bytes)
    }

    @MainActor
    func testCoordinateSafetyLimitStopsNavigationAndFitContentReturnsToDrawing() {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        model.drawing = makeDrawing()
        let surface = CanvasDocumentSurface(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        surface.apply(model, selecting: false, onSelection: nil)
        surface.layoutIfNeeded()
        surface.canvas.contentOffset.x += CanvasViewport.coordinateLimit * 2
        surface.viewportDidChange()
        surface.finishNavigation()
        XCTAssertTrue(model.isAtCoordinateLimit)
        XCTAssertLessThanOrEqual(surface.documentPoint(at: CGPoint(x: 600, y: 200)).x, CanvasViewport.coordinateLimit)
        model.navigateCanvas(.fitContent)
        surface.apply(model, selecting: false, onSelection: nil)
        surface.layoutIfNeeded()
        XCTAssertFalse(model.isAtCoordinateLimit)
        XCTAssertEqual(surface.currentViewport.center.x, model.contentBounds.midX, accuracy: 0.001)
        XCTAssertEqual(surface.currentViewport.center.y, model.contentBounds.midY, accuracy: 0.001)
    }

    @MainActor
    func testReferenceImageAndSelectionPersistIndependentlyOfInk() throws {
        let storage = temporaryStorage()
        let model = CanvasViewModel(storageURL: storage)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        try model.setReferenceImage(data: image, name: "Result.png", sourceID: "thread-1/attachment-2")
        let reference = try XCTUnwrap(model.referenceImage)
        model.drawing = makeDrawing()
        let crop = CGRect(x: 10, y: 20, width: 80, height: 60)
        try model.setExportBounds(crop)
        let snapshot = try XCTUnwrap(model.snapshot())
        XCTAssertEqual(UIImage(data: snapshot)?.size, crop.size)
        model.clear()
        XCTAssertTrue(model.drawing.strokes.isEmpty)
        XCTAssertEqual(model.referenceImage?.data, reference.data)
        model.undo()
        XCTAssertEqual(model.drawing.strokes.count, 1)
        XCTAssertEqual(model.exportBounds, crop)

        let restored = CanvasViewModel(storageURL: storage)
        XCTAssertEqual(restored.referenceImage?.sourceID, "thread-1/attachment-2")
        XCTAssertEqual(restored.referenceImage?.name, reference.name)
        XCTAssertEqual(restored.referenceImage?.data, reference.data)
        XCTAssertEqual(restored.selectedExportBounds, crop)
        XCTAssertEqual(restored.snapshot(), snapshot)
        try restored.setReferenceImage(data: image, name: "Next result.png", sourceID: "thread-1/attachment-3")
        XCTAssertNil(restored.selectedExportBounds, "A replacement image must not inherit the previous image's crop.")
        XCTAssertEqual(restored.exportBounds, reference.bounds)
        XCTAssertEqual(restored.drawing.strokes.count, 1, "Replacing the locked image preserves editable annotations.")
        try restored.setExportBounds(crop)
        try restored.setExportBounds(nil)
        XCTAssertEqual(restored.exportBounds, reference.bounds)
        restored.clearReferenceImage()
        XCTAssertNil(restored.referenceImage)
        XCTAssertEqual(restored.drawing.strokes.count, 1)
    }

    @MainActor
    func testInvalidReferenceAndSelectionDoNotReplaceCurrentDocument() throws {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        model.drawing = makeDrawing()
        let revision = model.revision
        let snapshot = model.snapshot()
        XCTAssertThrowsError(try model.setReferenceImage(data: Data("invalid image".utf8), name: "bad.png", sourceID: "source"))
        XCTAssertThrowsError(try model.setExportBounds(CGRect(x: 0, y: 0, width: 0, height: 100)))
        XCTAssertEqual(model.revision, revision)
        XCTAssertEqual(model.snapshot(), snapshot)
    }

    @MainActor
    func testEarlierDocumentsLoadWithoutViewportReferenceOrSelection() throws {
        var document = CanvasDocument(background: .gray)
        document.drawing = makeDrawing()
        document.exportBounds = document.drawing.bounds
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        encoded.removeValue(forKey: "referenceImage")
        encoded.removeValue(forKey: "selectedExportBounds")
        encoded.removeValue(forKey: "viewport")
        for version in [1, 2] {
            encoded["version"] = version
            let storage = temporaryStorage()
            try JSONSerialization.data(withJSONObject: encoded).write(to: storage)
            let model = CanvasViewModel(storageURL: storage)
            XCTAssertNil(model.storageError)
            XCTAssertEqual(model.documentID, document.id)
            XCTAssertEqual(model.background, .gray)
            XCTAssertEqual(model.drawing.strokes.count, 1)
            XCTAssertNil(model.referenceImage)
            XCTAssertNil(model.selectedExportBounds)
            XCTAssertNil(model.viewport)
        }
    }

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

    @MainActor
    func testSelectingAndDeletingReferencePreservesInkAndCanUndoAfterReload() throws {
        let storage = temporaryStorage()
        let model = CanvasViewModel(storageURL: storage)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).pngData { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        try model.setReferenceImage(data: image, name: "Saved reference.png", sourceID: "test")
        model.drawing = makeDrawing()
        let restored = CanvasViewModel(storageURL: storage)
        restored.isSelectingContent = true
        restored.selectContent(at: CGPoint(x: 180, y: 80), tolerance: 4)
        XCTAssertTrue(restored.isReferenceSelected)
        XCTAssertTrue(restored.selectedStrokeIndexes.isEmpty)
        restored.deleteSelectedContent()
        XCTAssertNil(restored.referenceImage)
        XCTAssertEqual(restored.drawing.strokes.count, 1)
        XCTAssertNil(CanvasViewModel(storageURL: storage).referenceImage)
        restored.undo()
        XCTAssertEqual(restored.referenceImage?.data, model.referenceImage?.data)
        XCTAssertEqual(restored.drawing.strokes.count, 1)
        restored.redo()
        XCTAssertNil(restored.referenceImage)
        XCTAssertFalse(restored.hasSelection)
    }

    @MainActor
    func testBoxSelectionDeletesOnlyIntersectingStrokesAndSelectAllDeletesBothLayers() throws {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        let first = makeDrawing()
        let other = makeDrawing(ink: .blue).transformed(using: CGAffineTransform(translationX: 300, y: 300))
        model.drawing = PKDrawing(strokes: first.strokes + other.strokes)
        model.selectContent(in: first.bounds.insetBy(dx: -10, dy: -10))
        XCTAssertEqual(model.selectedStrokeIndexes, [0])
        model.deleteSelectedContent()
        XCTAssertEqual(model.drawing.strokes.count, 1)
        XCTAssertEqual(model.drawing.strokes.first?.ink.color, .blue)
        model.undo()
        XCTAssertEqual(model.drawing.strokes.count, 2)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).pngData { _ in }
        try model.setReferenceImage(data: image, name: "Image.png", sourceID: "test")
        model.selectAllContent()
        model.deleteSelectedContent()
        XCTAssertFalse(model.hasContent)
        model.undo()
        XCTAssertEqual(model.drawing.strokes.count, 2)
        XCTAssertNotNil(model.referenceImage)
    }

    @MainActor
    func testResizeDuringToolGesturePreservesLiveInkAndOneUndoBoundary() {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        let surface = CanvasDocumentSurface(frame: CGRect(x: 0, y: 0, width: 480, height: 400))
        surface.apply(model, selecting: false, onSelection: nil)
        surface.layoutIfNeeded()
        let coordinator = CanvasView.Coordinator(viewModel: model)
        coordinator.surface = surface
        coordinator.canvasViewDidBeginUsingTool(surface.canvas)
        let offset = CGAffineTransform(translationX: surface.canvas.contentOffset.x, y: surface.canvas.contentOffset.y)
        surface.canvas.drawing = makeDrawing().transformed(using: offset)
        let expected = surface.documentDrawing(from: surface.canvas.drawing).bounds
        coordinator.canvasViewDrawingDidChange(surface.canvas)
        XCTAssertTrue(model.drawing.strokes.isEmpty)
        surface.frame.size = CGSize(width: 600, height: 400)
        surface.layoutIfNeeded()
        XCTAssertEqual(surface.canvas.drawing.strokes.count, 1)
        coordinator.canvasViewDidEndUsingTool(surface.canvas)
        surface.layoutIfNeeded()
        XCTAssertEqual(model.drawing.strokes.count, 1)
        XCTAssertEqual(model.drawing.bounds.minX, expected.minX, accuracy: 0.001)
        XCTAssertEqual(model.drawing.bounds.minY, expected.minY, accuracy: 0.001)
        XCTAssertEqual(surface.documentDrawing(from: surface.canvas.drawing).bounds.minX, expected.minX, accuracy: 0.001)
        model.undo()
        XCTAssertTrue(model.drawing.strokes.isEmpty)
        XCTAssertFalse(model.canUndo)
        model.redo()
        XCTAssertEqual(model.drawing.strokes.count, 1)
    }

    @MainActor
    func testSelectionChecksVisibleInkInsteadOfDiagonalBoundingBox() throws {
        let storage = temporaryStorage()
        let model = CanvasViewModel(storageURL: storage)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).pngData { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        try model.setReferenceImage(data: image, name: "Reference.png", sourceID: "selection")
        let referenceData = try XCTUnwrap(model.referenceImage).data
        let diagonal = drawingThrough([CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 60), CGPoint(x: 100, y: 100)])
        model.drawing = diagonal
        model.selectContent(at: CGPoint(x: 90, y: 30), tolerance: 4)
        XCTAssertTrue(model.isReferenceSelected)
        XCTAssertTrue(model.selectedStrokeIndexes.isEmpty)
        model.selectContent(in: CGRect(x: 85, y: 25, width: 10, height: 10))
        XCTAssertTrue(model.selectedStrokeIndexes.isEmpty)
        model.selectContent(at: CGPoint(x: 65, y: 55), tolerance: 4)
        XCTAssertEqual(model.selectedStrokeIndexes, [0], "Tolerance follows the nearby visible ink.")
        model.selectContent(at: CGPoint(x: 75, y: 45), tolerance: 4)
        XCTAssertTrue(model.isReferenceSelected)
        model.selectContent(at: CGPoint(x: 60, y: 60), tolerance: 4)
        XCTAssertEqual(model.selectedStrokeIndexes, [0])
        XCTAssertFalse(model.isReferenceSelected)
        model.deleteSelectedContent()
        XCTAssertTrue(model.drawing.strokes.isEmpty)
        XCTAssertNotNil(model.referenceImage)
        model.undo()
        XCTAssertEqual(model.drawing, diagonal)
        model.redo()
        XCTAssertEqual(CanvasViewModel(storageURL: storage).referenceImage?.data, referenceData)
        XCTAssertTrue(CanvasViewModel(storageURL: storage).drawing.strokes.isEmpty)
    }

    @MainActor
    func testClosedCurveInteriorIsNotInkAndIntersectingBoxStillSelects() {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        let circle = (0...32).map { index in
            let angle = CGFloat(index) * .pi / 16
            return CGPoint(x: 100 + cos(angle) * 60, y: 100 + sin(angle) * 60)
        }
        model.drawing = drawingThrough(circle)
        model.selectContent(at: CGPoint(x: 100, y: 100), tolerance: 12)
        XCTAssertFalse(model.hasSelection)
        model.selectContent(in: CGRect(x: 90, y: 90, width: 20, height: 20))
        XCTAssertFalse(model.hasSelection)
        model.selectContent(in: CGRect(x: 155, y: 95, width: 10, height: 10))
        XCTAssertEqual(model.selectedStrokeIndexes, [0])
    }

    @MainActor
    func testSelectionHonorsStrokeTransformMaskWidthAndTopmostOrder() {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        var masked = makeDrawing().strokes[0]
        masked.mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 60, height: 100))
        masked.transform = CGAffineTransform(translationX: 200, y: 100)
        model.drawing = PKDrawing(strokes: [masked])
        model.selectContent(at: CGPoint(x: 280, y: 140), tolerance: 2)
        XCTAssertFalse(model.hasSelection, "Erased portions of a transformed stroke are not selectable ink.")
        model.selectContent(at: CGPoint(x: 240, y: 144), tolerance: 2)
        XCTAssertEqual(model.selectedStrokeIndexes, [0], "The probe includes visible line width, not just the centerline.")
        model.selectContent(in: CGRect(x: 275, y: 135, width: 10, height: 10))
        XCTAssertFalse(model.hasSelection)
        model.drawing = PKDrawing(strokes: makeDrawing().strokes + makeDrawing(ink: .blue).strokes)
        model.selectContent(at: CGPoint(x: 60, y: 40), tolerance: 4)
        XCTAssertEqual(model.selectedStrokeIndexes, [1])
    }

    @MainActor
    func testCropHasItsOwnChronologicalUndoStepAndPersistsAfterRedo() throws {
        let storage = temporaryStorage()
        let model = CanvasViewModel(storageURL: storage)
        let first = makeDrawing()
        let second = PKDrawing(strokes: first.strokes + makeDrawing(ink: .blue).strokes)
        let a = CGRect(x: 10, y: 20, width: 80, height: 60)
        let b = CGRect(x: 20, y: 30, width: 40, height: 30)
        let camera = CanvasViewport(center: CGPoint(x: 100, y: 200), zoom: 0.5)
        model.drawing = first
        try model.setExportBounds(a)
        model.drawing = second
        try model.setExportBounds(b)
        model.saveViewport(camera)
        model.undo()
        XCTAssertEqual(model.drawing.strokes.count, 2, "Undo first reverses the latest crop edit only.")
        XCTAssertEqual(model.selectedExportBounds, a)
        model.undo()
        XCTAssertEqual(model.drawing, first)
        XCTAssertEqual(model.selectedExportBounds, a)
        model.undo()
        XCTAssertNil(model.selectedExportBounds)
        XCTAssertEqual(model.drawing, first)
        model.redo(); model.redo(); model.redo()
        XCTAssertEqual(model.drawing.strokes.count, 2)
        XCTAssertEqual(model.selectedExportBounds, b)
        XCTAssertEqual(model.viewport, camera)
        let restored = CanvasViewModel(storageURL: storage)
        XCTAssertEqual(restored.selectedExportBounds, b)
        XCTAssertEqual(UIImage(data: try XCTUnwrap(restored.snapshot()))?.size, b.size)
    }

    @MainActor
    func testCropAfterUndoInvalidatesRedoAndDeleteCropUndoIsOrdered() throws {
        let model = CanvasViewModel(storageURL: temporaryStorage())
        model.drawing = makeDrawing()
        model.selectAllContent(); model.deleteSelectedContent()
        let crop = CGRect(x: 10, y: 20, width: 80, height: 60)
        try model.setExportBounds(crop)
        model.undo()
        XCTAssertNil(model.selectedExportBounds)
        XCTAssertTrue(model.drawing.strokes.isEmpty)
        model.undo()
        XCTAssertEqual(model.drawing.strokes.count, 1)
        XCTAssertTrue(model.canRedo)
        try model.setExportBounds(crop)
        XCTAssertFalse(model.canRedo)
        model.redo()
        XCTAssertEqual(model.selectedExportBounds, crop)
        XCTAssertEqual(model.drawing.strokes.count, 1)
    }

    private func drawingThrough(_ locations: [CGPoint]) -> PKDrawing {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                          size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_000)))])
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

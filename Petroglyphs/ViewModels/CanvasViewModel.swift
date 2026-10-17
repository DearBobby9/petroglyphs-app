import PencilKit
import SwiftUI

@Observable
@MainActor
final class CanvasViewModel {
    private var document: CanvasDocument
    private let storageURL: URL
    private var protectsUnreadableDocument = false
    private(set) var storageError: String?
    private struct EditState {
        let drawing: PKDrawing
        let referenceImage: CanvasDocumentReference?
        let exportBounds: CGRect?
    }
    private var undoEdits: [EditState] = []
    private var redoEdits: [EditState] = []
    var isSelectingContent = false {
        didSet { if !isSelectingContent { clearSelection() } }
    }
    private(set) var selectedStrokeIndexes: Set<Int> = []
    private(set) var isReferenceSelected = false
    var hasSelection: Bool { !selectedStrokeIndexes.isEmpty || isReferenceSelected }
    var selectionDescription: String {
        let ink = selectedStrokeIndexes.count
        if isReferenceSelected { return ink == 0 ? "Reference image selected" : "Reference image and \(ink) strokes selected" }
        return ink == 0 ? "Tap an object or drag a box to select." : "\(ink) strokes selected"
    }
    var contentSelectionBounds: CGRect? {
        var bounds = isReferenceSelected ? (referenceImage?.bounds ?? .null) : CGRect.null
        for index in selectedStrokeIndexes where drawing.strokes.indices.contains(index) {
            bounds = bounds.union(drawing.strokes[index].renderBounds)
        }
        return bounds.isNull ? nil : bounds
    }
    private var lastDrawingGestureID: UUID?

    var drawing: PKDrawing {
        get { document.drawing }
        set { updateDrawing(newValue) }
    }

    var background: CanvasBackground {
        get { document.background }
        set {
            guard newValue != document.background else { return }
            document.background = newValue
            documentChanged()
        }
    }

    var documentID: UUID { document.id }
    var revision: Int { document.revision }
    var exportBounds: CGRect { document.exportBounds }
    var contentBounds: CGRect { document.contentBounds }
    var referenceImage: CanvasDocumentReference? { document.referenceImage }
    var selectedExportBounds: CGRect? { document.selectedExportBounds }
    var viewport: CanvasViewport? { document.viewport }
    private(set) var viewportCommand: CanvasViewportCommand?
    private(set) var viewportCommandID = 0
    private(set) var isAtCoordinateLimit = false
    var hasContent: Bool { !drawing.strokes.isEmpty || referenceImage != nil }
    var snapshotFilename: String { "canvas-\(documentID.uuidString.lowercased())-r\(revision).png" }
    var canUndo: Bool { !undoEdits.isEmpty }
    var canRedo: Bool { !redoEdits.isEmpty }

    var showCastSuccess = false
    var showWipeAnimation = false
    var isCasting = false
    var castError: String?

    private var drawingStartTime: Date?
    private let exporter = CanvasExporter()

    init(storageURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.storageURL = storageURL ?? URL.applicationSupportDirectory
            .appending(path: "Petroglyphs/Canvas/active-canvas.json")
        let darkMode = defaults.bool(forKey: "darkModeEnabled")
        let fallback: CanvasBackground = darkMode ? .charcoal : .white
        let key = darkMode ? "darkCanvasBackgroundHex" : "canvasBackgroundHex"
        let background = defaults.string(forKey: key).flatMap(CanvasBackground.init(rawValue:)) ?? fallback
        document = CanvasDocument(background: background)

        if FileManager.default.fileExists(atPath: self.storageURL.path) {
            do {
                document = try JSONDecoder().decode(CanvasDocument.self, from: Data(contentsOf: self.storageURL))
            } catch {
                protectsUnreadableDocument = true
                storageError = "The saved canvas could not be opened. Its original file is preserved; current edits cannot be saved. \(error.localizedDescription)"
            }
        } else {
            save()
        }
    }

    @discardableResult
    func save() -> Bool {
        guard !protectsUnreadableDocument else { return false }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(document).write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            storageError = nil
            return true
        } catch {
            storageError = "The canvas could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    func snapshot() -> Data? {
        exporter.pngData(document: document)
    }

    func navigateCanvas(_ command: CanvasViewportCommand) {
        viewportCommand = command
        viewportCommandID += 1
    }

    func completeCanvasNavigation(_ commandID: Int) {
        if viewportCommandID == commandID { viewportCommand = nil }
    }

    func saveViewport(_ viewport: CanvasViewport, atCoordinateLimit: Bool = false) {
        guard viewport.isValid else { return }
        isAtCoordinateLimit = atCoordinateLimit
        guard viewport != document.viewport else { return }
        document.viewport = viewport
        // Moving the camera does not change snapshot identity or drawing undo.
        save()
    }

    func setReferenceImage(data: Data, name: String, sourceID: String) throws {
        let reference = try CanvasDocumentReference(data: data, name: name, sourceID: sourceID)
        recordEdit()
        document.referenceImage = reference
        document.selectedExportBounds = nil
        refreshExportBounds()
        documentChanged()
        navigateCanvas(.fitContent)
    }

    func clearReferenceImage() {
        guard referenceImage != nil else { return }
        recordEdit()
        document.referenceImage = nil
        refreshExportBounds()
        documentChanged()
    }

    func setExportBounds(_ bounds: CGRect?) throws {
        if let bounds, !CanvasDocument.isValid(bounds) { throw CanvasDocument.DocumentError.invalidBounds }
        guard bounds != document.selectedExportBounds else { return }
        // Crop is an explicit edit, with its own place in chronological undo.
        recordEdit()
        document.selectedExportBounds = bounds
        refreshExportBounds()
        documentChanged()
    }

    private func refreshExportBounds() {
        document.exportBounds = document.selectedExportBounds ?? document.contentBounds
    }

    private func documentChanged(saveImmediately: Bool = true) {
        document.revision += 1
        if saveImmediately { save() }
    }

    // One tool gesture can deliver several drawing updates, including a final
    // update after tool-up. Keep its first snapshot as the undo boundary.
    func updateDrawing(_ drawing: PKDrawing, gestureID: UUID? = nil, saveImmediately: Bool = true) {
        guard drawing != document.drawing else { return }
        if gestureID == nil || gestureID != lastDrawingGestureID {
            recordEdit()
        }
        lastDrawingGestureID = gestureID
        replaceDrawing(drawing, saveImmediately: saveImmediately)
    }

    private var editState: EditState {
        EditState(drawing: document.drawing, referenceImage: document.referenceImage, exportBounds: document.selectedExportBounds)
    }

    private func recordEdit() {
        undoEdits.append(editState)
        if undoEdits.count > 100 { undoEdits.removeFirst() }
        redoEdits.removeAll()
        lastDrawingGestureID = nil
        clearSelection()
    }

    func clearSelection() {
        selectedStrokeIndexes = []
        isReferenceSelected = false
    }

    func selectContent(in bounds: CGRect) {
        guard CanvasDocument.isValid(bounds) else { clearSelection(); return }
        selectedStrokeIndexes = Set(drawing.strokes.indices.filter { strokeHasInk(drawing.strokes[$0], in: bounds) })
        isReferenceSelected = referenceImage.map { $0.bounds.intersects(bounds) } ?? false
    }

    func selectContent(at point: CGPoint, tolerance: CGFloat) {
        clearSelection()
        guard point.x.isFinite, point.y.isFinite, tolerance.isFinite, tolerance >= 0 else { return }
        let radius = max(0.5, tolerance)
        let probe = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        // Ink is above the image. A tap selects the topmost matching object.
        if let index = drawing.strokes.indices.reversed().first(where: {
            strokeHasInk(drawing.strokes[$0], in: probe, circularProbe: probe)
        }) {
            selectedStrokeIndexes = [index]
        } else if referenceImage?.bounds.contains(point) == true {
            isReferenceSelected = true
        }
    }

    private func strokeHasInk(_ stroke: PKStroke, in bounds: CGRect, circularProbe: CGRect? = nil) -> Bool {
        let overlap = stroke.renderBounds.intersection(bounds)
        guard CanvasDocument.isValid(overlap) else { return false }
        if circularProbe == nil, bounds.contains(stroke.renderBounds), stroke.mask == nil { return true }

        // Ask PencilKit for the visible ink, including width, transforms and
        // eraser masks. A bounding box alone includes empty diagonal/circle areas.
        // Small tiles cap temporary memory even for a large drag selection.
        let isolated = PKDrawing(strokes: [stroke])
        let tileSize: CGFloat = 256
        var y = overlap.minY
        while y < overlap.maxY {
            var x = overlap.minX
            while x < overlap.maxX {
                let tile = CGRect(x: x, y: y, width: min(tileSize, overlap.maxX - x), height: min(tileSize, overlap.maxY - y))
                let hit = autoreleasepool {
                    let rendered = isolated.image(from: tile, scale: 1)
                    let visible: UIImage
                    if let circularProbe {
                        // UIKit handles image orientation and document-down Y
                        // consistently for both the tolerance circle and ink.
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1
                        format.opaque = false
                        visible = UIGraphicsImageRenderer(size: tile.size, format: format).image { renderer in
                            renderer.cgContext.addEllipse(in: circularProbe.offsetBy(dx: -tile.minX, dy: -tile.minY))
                            renderer.cgContext.clip()
                            rendered.draw(in: CGRect(origin: .zero, size: tile.size))
                        }
                    } else {
                        visible = rendered
                    }
                    guard let image = visible.cgImage else { return false }
                    let width = image.width, height = image.height
                    var alpha = [UInt8](repeating: 0, count: width * height * 4)
                    return alpha.withUnsafeMutableBytes { bytes in
                        guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                        return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
                    }
                }
                if hit { return true }
                x += tileSize
            }
            y += tileSize
        }
        return false
    }

    func selectAllContent() {
        selectedStrokeIndexes = Set(drawing.strokes.indices)
        isReferenceSelected = referenceImage != nil
    }

    func deleteSelectedContent() {
        guard hasSelection else { return }
        let indexes = selectedStrokeIndexes
        let removeReference = isReferenceSelected
        recordEdit()
        document.drawing = PKDrawing(strokes: document.drawing.strokes.enumerated().compactMap {
            indexes.contains($0.offset) ? nil : $0.element
        })
        if removeReference { document.referenceImage = nil }
        refreshExportBounds()
        documentChanged()
    }

    func undo() {
        guard let previous = undoEdits.popLast() else { return }
        redoEdits.append(editState)
        restoreEdit(previous)
    }

    func redo() {
        guard let next = redoEdits.popLast() else { return }
        undoEdits.append(editState)
        restoreEdit(next)
    }

    private func restoreEdit(_ state: EditState) {
        lastDrawingGestureID = nil
        clearSelection()
        document.drawing = state.drawing
        document.referenceImage = state.referenceImage
        document.selectedExportBounds = state.exportBounds
        refreshExportBounds()
        documentChanged()
    }

    private func replaceDrawing(_ drawing: PKDrawing, saveImmediately: Bool = true) {
        document.drawing = drawing
        refreshExportBounds()
        if !drawing.strokes.isEmpty { onFirstStroke() }
        documentChanged(saveImmediately: saveImmediately)
    }

    func onFirstStroke() {
        if drawingStartTime == nil {
            drawingStartTime = Date()
        }
    }

    func cast(
        combo: Combo?,
        networkService: NetworkService,
        offlineQueue: OfflineQueue,
        serverURL: URL?,
        isConnected: Bool,
        pairingCode: String? = nil,
        codexTarget: CodexChatTarget? = nil,
        requiresCodexThread: Bool = false,
        backgroundColor: UIColor = .white,
        onSubmission: ((SubmissionResponse, SubmissionPayload) -> Void)? = nil
    ) {
        guard !isCasting, hasContent else { return }
        if requiresCodexThread {
            guard let codexTarget, !codexTarget.thread.id.isEmpty, codexTarget.serverURL == serverURL else {
                castError = "Choose a Codex chat before sending."
                return
            }
            guard isConnected, serverURL != nil else {
                castError = "Reconnect to your Mac before sending to Codex."
                return
            }
            guard codexTarget.host.canSelect else {
                castError = codexTarget.host.unavailabilityReason
                return
            }
        }

        let duration = drawingStartTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
        let documentSnapshot = document
        let payload: SubmissionPayload
        castError = nil
        do {
            // Export before starting async work so later drawing or chat edits cannot change this send.
            let export = try exporter.export(
                document: documentSnapshot,
                duration: duration
            )
            let code = pairingCode?.isEmpty == false ? pairingCode : nil
            payload = SubmissionPayload(
                image: export.imageBase64,
                strokeMetadata: export.strokeMetadata,
                combo: combo,
                pairingCode: code,
                threadId: codexTarget?.thread.id,
                hostId: codexTarget?.host.id
            )
        } catch {
            castError = error.localizedDescription
            return
        }
        isCasting = true

        Task {
            do {
                if isConnected, let url = serverURL {
                    let receipt = try await networkService.submit(payload, to: url)
                    onSubmission?(receipt, payload)
                } else {
                    offlineQueue.enqueue(payload)
                }

                isCasting = false
                showCastSuccess = true
            } catch {
                isCasting = false
                castError = error.localizedDescription
            }
        }
    }

    func clear() {
        guard !drawing.strokes.isEmpty else { return }
        drawing = PKDrawing()
        showWipeAnimation = true
        drawingStartTime = nil
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            showWipeAnimation = false
        }
    }
}

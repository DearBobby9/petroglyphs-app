import Foundation
import CoreGraphics

/// Opt-in debug diagnostics. The payload has only counters, geometry, and
/// booleans; it never records conversation content or destination identifiers.
nonisolated final class InteractionDiagnostics: @unchecked Sendable {
    static let shared = InteractionDiagnostics()

    enum Event: String, CaseIterable {
        case canvasMake, canvasUpdate, canvasApply, canvasLayout, canvasScroll, canvasZoom, canvasLayers
        case canvasDrawingCallback, canvasDrawingCommit, canvasViewportSave, canvasPosition
        case canvasPositionInitial, canvasPositionResize, canvasPositionRecenter, canvasPositionCommand, canvasWindowRebuild
        case workspaceChromePreference, chatPaneMeasure, chatPanePlace
        case chatRowsPreference, chatBlocksPreference, chatContentPreference, chatGeometry
        case chatMetricsIgnored, chatMetricsChanged, chatReadingSaveScheduled, chatReadingSaveCompleted
        case chatRestore, chatRestoreAttempt, chatRestoreMissingFrame, chatRestoreCompleted
        case chatScrollToBegin, chatScrollToEnd, chatNativeScrollBegin, chatNativeScrollEnd
        case chatScrollCaptureBegin, chatScrollCaptureEnd, chatPaneMeasured, chatPanePlaced
        case markdownParseBegin, markdownParseEnd, chatTurnGroupingBegin, chatTurnGroupingEnd
        case conversationDecodeBegin, conversationDecodeEnd, historyApplyBegin, historyApplyEnd
        case stateSaveBegin, stateSaveEnd, historySaveBegin, historySaveEnd
        case imageCacheReadBegin, imageCacheReadEnd, imageCacheWriteBegin, imageCacheWriteEnd
        case imageDecodeBegin, imageDecodeEnd
        case resultImagePublishBegin, resultImagePublishEnd
        case draftImageDecodeBegin, draftImageDecodeEnd, draftImagePublishBegin, draftImagePublishEnd
        case composerUpdateBegin, composerUpdateEnd, composerTextReplaceBegin, composerTextReplaceEnd
        case composerMeasureBegin, composerMeasureEnd, composerNativeMeasureBegin, composerNativeMeasureEnd
        case composerScrollingUpdateBegin, composerScrollingUpdateEnd
        case composerMeasurement
        case composerIntrinsicInvalidationBegin, composerIntrinsicInvalidationEnd
        case composerLayoutBegin, composerLayoutEnd, composerHeightPreferenceBegin, composerHeightPreferenceEnd
        case composerSendBegin, composerSendAccepted, composerSendEnd
    }

    enum Metric: String {
        case canvasBounds, canvasOffset, canvasZoom, paneProposal, paneBounds, chatGeometry, chatContentFrame
        case composerProposal, composerMeasurement, composerBounds, composerHeight, draftImageSize, resultImageSize
    }

    enum Flag: String {
        case chatHasPendingRestore, chatHasScrollView, chatAnchorExists, chatAnchorFrameExists
        case composerScrollEnabled, composerCanSubmit
    }

    let isEnabled: Bool
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "petroglyphs.ui-diagnostics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var startedAt: TimeInterval?
    private var mainHeartbeatAt: TimeInterval?
    private var mainHeartbeatCount = 0
    private var heartbeatPending = false
    private var counts = Dictionary(uniqueKeysWithValues: Event.allCases.map { ($0.rawValue, 0) })
    private var geometry: [String: [Double]] = [:]
    private var flags: [String: Bool] = [:]
    private var lastEvent: String?
    private var lastEventAt: TimeInterval?

    private init() {
        #if DEBUG
        isEnabled = ProcessInfo.processInfo.arguments.contains("-PetroglyphsTraceUI")
        #else
        isEnabled = false
        #endif
    }

    func startIfEnabled() {
        guard isEnabled else { return }
        lock.lock()
        guard timer == nil else { lock.unlock(); return }
        startedAt = Date().timeIntervalSince1970
        let timer = DispatchSource.makeTimerSource(queue: writer)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.writeSnapshot() }
        self.timer = timer
        lock.unlock()
        timer.resume()
    }

    func record(_ event: Event, geometry: [Metric: [Double]] = [:], flags: [Flag: Bool] = [:]) {
        guard isEnabled else { return }
        lock.lock()
        counts[event.rawValue, default: 0] += 1
        lastEvent = event.rawValue
        lastEventAt = Date().timeIntervalSince1970
        for (key, value) in geometry where value.allSatisfy(\.isFinite) { self.geometry[key.rawValue] = value }
        for (key, value) in flags { self.flags[key.rawValue] = value }
        lock.unlock()
    }

    func canvas(_ event: Event, bounds: CGRect, offset: CGPoint, zoom: CGFloat) {
        guard isEnabled else { return }
        record(event, geometry: [
            .canvasBounds: [bounds.origin.x, bounds.origin.y, bounds.width, bounds.height].map(Double.init),
            .canvasOffset: [offset.x, offset.y].map(Double.init), .canvasZoom: [Double(zoom)]
        ])
    }

    private func writeSnapshot() {
        let now = Date().timeIntervalSince1970
        lock.lock()
        let wasPending = heartbeatPending
        heartbeatPending = true
        let snapshot: [String: Any] = [
            "writtenAt": now, "startedAt": startedAt ?? now,
            "mainHeartbeatAt": mainHeartbeatAt.map { $0 as Any } ?? NSNull(),
            "mainHeartbeatCount": mainHeartbeatCount, "mainHeartbeatPending": wasPending,
            "counts": counts, "geometry": geometry, "flags": flags,
            "lastEvent": lastEvent.map { $0 as Any } ?? NSNull(),
            "lastEventAt": lastEventAt.map { $0 as Any } ?? NSNull()
        ]
        lock.unlock()

        // Leave at most one heartbeat queued if the main thread stops servicing
        // work. The writer can still report the last successful heartbeat.
        if !wasPending {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.mainHeartbeatAt = Date().timeIntervalSince1970
                self.mainHeartbeatCount += 1
                self.heartbeatPending = false
                self.lock.unlock()
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
        let destination = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("petroglyphs-ui-trace.json")
        try? data.write(to: destination, options: .atomic)
    }
}

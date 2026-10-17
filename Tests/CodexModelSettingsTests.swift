import XCTest

final class CodexModelSettingsTests: XCTestCase {
    @MainActor
    func testLateCatalogueCannotReplaceAnotherHostOrKeepPreviousHostOptions() async {
        let network = ModelSettingsNetworkFixture()
        let model = CodexModelSettingsModel(network: network, now: { ModelSettingsNetworkFixture.observedAt })
        XCTAssertFalse(model.matches(from: server, hostId: "local", threadId: "local-chat"))
        await model.load(from: server, hostId: "local", threadId: "local-chat")
        XCTAssertTrue(model.matches(from: server, hostId: "local", threadId: "local-chat"))
        XCTAssertFalse(model.matches(from: URL(string: "http://other.invalid/device/test-pair")!, hostId: "local", threadId: "local-chat"))
        await network.suspendCatalogue(host: "remote")
        let old = Task { await model.load(from: server, hostId: "remote", threadId: "remote-chat") }
        await network.waitForCatalogueRead()
        XCTAssertTrue(model.matches(from: server, hostId: "remote", threadId: "remote-chat"))
        XCTAssertFalse(model.matches(from: server, hostId: "local", threadId: "local-chat"))
        XCTAssertNil(model.catalogue, "A host change must discard the previous host's options immediately.")
        XCTAssertNil(model.settings)
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.validationMessage(for: nil))
        await model.load(from: server, hostId: "local", threadId: "new-local-chat")
        await network.finishCatalogueRead()
        await old.value
        XCTAssertEqual(model.catalogue?.hostId, "local")
        XCTAssertEqual(model.settings?.threadId, "new-local-chat")
        XCTAssertTrue(model.matches(from: server, hostId: "local", threadId: "new-local-chat"))
        XCTAssertFalse(model.matches(from: server, hostId: "remote", threadId: "remote-chat"))
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
    }

    @MainActor
    func testLateSettingsCannotReplaceAnotherThreadOnTheSameHost() async {
        let network = ModelSettingsNetworkFixture()
        await network.suspendSettings(thread: "old-chat")
        let model = CodexModelSettingsModel(network: network, now: { ModelSettingsNetworkFixture.observedAt })
        let old = Task { await model.load(from: server, hostId: "local", threadId: "old-chat") }
        await network.waitForSettingsRead()
        await model.load(from: server, hostId: "local", threadId: "new-chat")
        await network.finishSettingsRead()
        await old.value
        XCTAssertEqual(model.catalogue?.hostId, "local")
        XCTAssertEqual(model.settings?.threadId, "new-chat")
        XCTAssertTrue(model.matches(from: server, hostId: "local", threadId: "new-chat"))
        XCTAssertFalse(model.matches(from: server, hostId: "local", threadId: "old-chat"))
        XCTAssertNil(model.error)
    }

    @MainActor
    func testMismatchedResponseScopesAreRejectedIndependently() async {
        let network = ModelSettingsNetworkFixture()
        let model = CodexModelSettingsModel(network: network, now: { ModelSettingsNetworkFixture.observedAt })
        await network.overrideCatalogue(ModelSettingsNetworkFixture.catalogue(host: "wrong-host"))
        await model.load(from: server, hostId: "local", threadId: "chat")
        XCTAssertNil(model.catalogue)
        XCTAssertEqual(model.settings?.threadId, "chat")
        XCTAssertNotNil(model.error)

        await network.overrideCatalogue(nil)
        for (host, thread) in [("wrong-host", "chat"), ("local", "wrong-thread")] {
            await network.overrideSettings(CodexThreadModelSettings(hostId: host, threadId: thread,
                model: "model-a", reasoningEffort: "high", observedAt: "2026-10-16T12:00:00Z"))
            await model.load(from: server, hostId: "local", threadId: "chat")
            XCTAssertEqual(model.catalogue?.hostId, "local")
            XCTAssertNil(model.settings)
            XCTAssertNotNil(model.error)
        }
    }

    @MainActor
    func testIndependentReadFailuresPreserveTheSuccessfulResult() async {
        let network = ModelSettingsNetworkFixture()
        let model = CodexModelSettingsModel(network: network, now: { ModelSettingsNetworkFixture.observedAt })
        await network.configureFailures(catalogue: true, settings: false)
        await model.load(from: server, hostId: "local", threadId: "chat")
        XCTAssertNil(model.catalogue)
        XCTAssertEqual(model.settings?.model, "model-a")
        XCTAssertNotNil(model.validationMessage(for: explicitSelection))
        XCTAssertNil(model.validationMessage(for: nil))
        XCTAssertTrue(model.error?.contains("Available models") == true)

        await network.configureFailures(catalogue: false, settings: true)
        await model.load(from: server, hostId: "local", threadId: "chat")
        XCTAssertNotNil(model.catalogue)
        XCTAssertNil(model.settings)
        XCTAssertNil(model.validationMessage(for: explicitSelection))
        XCTAssertTrue(model.error?.contains("Chat settings") == true)

        await network.configureFailures(catalogue: false, settings: false)
        await model.load(from: server, hostId: "local", threadId: "chat")
        XCTAssertNil(model.error)
        XCTAssertNotNil(model.catalogue)
        XCTAssertNotNil(model.settings)
    }

    @MainActor
    func testSelectionRequiresSupportedEffortAndFreshCatalogueButFollowChatDoesNot() async {
        let network = ModelSettingsNetworkFixture()
        var now = ModelSettingsNetworkFixture.observedAt
        let model = CodexModelSettingsModel(network: network, now: { now })
        XCTAssertNil(model.validationMessage(for: nil))
        await model.load(from: server, hostId: "local", threadId: nil)
        XCTAssertNil(model.settings)
        let settingsReadCount = await network.settingsReadCount
        XCTAssertEqual(settingsReadCount, 0, "A new project chat has no thread settings to fetch.")
        XCTAssertNil(model.validationMessage(for: explicitSelection))
        XCTAssertNotNil(model.validationMessage(for: CodexDraftModelSelection(model: "model-a", reasoningEffort: nil)))
        XCTAssertNotNil(model.validationMessage(for: CodexDraftModelSelection(model: "model-a", reasoningEffort: "unsupported")))
        XCTAssertNotNil(model.validationMessage(for: CodexDraftModelSelection(model: "missing-model", reasoningEffort: "high")))
        XCTAssertEqual(model.model(named: "model-a")?.displayName, "Model A")

        now = now.addingTimeInterval(300)
        XCTAssertNotNil(model.validationMessage(for: explicitSelection), "An open picker must not keep an expired selection valid.")
        XCTAssertNil(model.validationMessage(for: nil))
        await network.overrideCatalogue(ModelSettingsNetworkFixture.catalogue(host: "local", expiresAfter: 600))
        await model.load(from: server, hostId: "local", threadId: nil)
        XCTAssertNotNil(model.validationMessage(for: explicitSelection), "Freshness is bounded to five minutes from observation.")

        await network.overrideCatalogue(CodexModelCatalog(hostId: "remote", status: "unavailable", source: nil,
            observedAt: nil, expiresAt: nil, models: [], reason: "not_configured"))
        await model.load(from: server, hostId: "remote", threadId: nil)
        XCTAssertNotNil(model.validationMessage(for: explicitSelection))
        XCTAssertNil(model.validationMessage(for: nil))
        XCTAssertNil(model.model(named: "model-a"))

        await network.overrideCatalogue(ModelSettingsNetworkFixture.catalogue(host: "local", observedAt: now, inputModalities: ["image"]))
        await model.load(from: server, hostId: "local", threadId: nil)
        XCTAssertNotNil(model.validationMessage(for: explicitSelection))
        XCTAssertNotNil(model.validationMessage(for: explicitSelection, hasImages: true))
        XCTAssertNil(model.validationMessage(for: nil, hasImages: true))
    }

    @MainActor
    func testObservationRefreshesAtTheCatalogueExpiryAndClearsExpiredOptions() async {
        let network = ModelSettingsNetworkFixture()
        var now = ModelSettingsNetworkFixture.observedAt.addingTimeInterval(240)
        let model = CodexModelSettingsModel(network: network, now: { now })
        var waits: [TimeInterval] = []
        let observing = Task {
            await model.observe(from: server, hostId: "local", threadId: nil) { interval in
                waits.append(interval)
                guard waits.count == 1 else { throw CancellationError() }
                now = now.addingTimeInterval(interval)
                await network.overrideCatalogue(ModelSettingsNetworkFixture.catalogue(host: "local", observedAt: now))
                await network.suspendCatalogue(host: "local")
            }
        }
        await network.waitForCatalogueRead()
        XCTAssertEqual(waits, [60], "A t240 read of a catalogue expiring at t300 must wait only 60 seconds.")
        XCTAssertEqual(now, ModelSettingsNetworkFixture.observedAt.addingTimeInterval(300))
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.catalogue, "Expiry must visibly invalidate the old options while refreshing.")
        await network.finishCatalogueRead()
        await observing.value
        let readCount = await network.catalogueReadCount
        XCTAssertEqual(readCount, 2)
        XCTAssertEqual(waits, [60, 300])
        XCTAssertNil(model.validationMessage(for: explicitSelection))
    }

    @MainActor
    func testObservationRetriesFailedUnavailableAndExpiredCataloguesWithoutSpinning() async {
        for state in ["failed", "unavailable", "expired"] {
            let network = ModelSettingsNetworkFixture()
            var now = ModelSettingsNetworkFixture.observedAt
            if state == "failed" { await network.configureFailures(catalogue: true, settings: false) }
            if state == "unavailable" {
                await network.overrideCatalogue(CodexModelCatalog(hostId: "local", status: "unavailable", source: nil,
                    observedAt: nil, expiresAt: nil, models: [], reason: "source_unavailable"))
            }
            if state == "expired" { now = now.addingTimeInterval(300) }
            let model = CodexModelSettingsModel(network: network, now: { now })
            var waits: [TimeInterval] = []
            await model.observe(from: server, hostId: "local", threadId: nil) { interval in
                waits.append(interval)
                guard waits.count < 2 else { throw CancellationError() }
                now = now.addingTimeInterval(interval)
            }
            XCTAssertEqual(waits.count, 2)
            XCTAssertTrue(waits.allSatisfy { $0 > 0 && $0 <= 30 }, "\(state) must retry within 30 seconds without a zero-delay loop.")
            let readCount = await network.catalogueReadCount
            XCTAssertEqual(readCount, 2, "A cancelled wait must end observation.")
            XCTAssertNotNil(model.validationMessage(for: explicitSelection))
            XCTAssertNil(model.validationMessage(for: nil, hasImages: true))
        }
    }

    private var server: URL { URL(string: "http://test.invalid/device/test-pair")! }
    private var explicitSelection: CodexDraftModelSelection { CodexDraftModelSelection(model: "model-a", reasoningEffort: "high") }
}

private actor ModelSettingsNetworkFixture: CodexModelSettingsNetworking {
    static let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private var catalogueOverride: CodexModelCatalog?
    private var settingsOverride: CodexThreadModelSettings?
    private var catalogueFails = false
    private var settingsFails = false
    private var suspendedHost: String?
    private var suspendedThread: String?
    private var catalogueStarted = false
    private var settingsStarted = false
    private var catalogueWaiter: CheckedContinuation<Void, Never>?
    private var settingsWaiter: CheckedContinuation<Void, Never>?
    private var catalogueContinuation: CheckedContinuation<Void, Never>?
    private var settingsContinuation: CheckedContinuation<Void, Never>?
    var catalogueReadCount = 0
    var settingsReadCount = 0

    func configureFailures(catalogue: Bool, settings: Bool) { catalogueFails = catalogue; settingsFails = settings }
    func overrideCatalogue(_ value: CodexModelCatalog?) { catalogueOverride = value }
    func overrideSettings(_ value: CodexThreadModelSettings?) { settingsOverride = value }
    func suspendCatalogue(host: String) { suspendedHost = host }
    func suspendSettings(thread: String) { suspendedThread = thread }
    func waitForCatalogueRead() async {
        if catalogueStarted { return }
        await withCheckedContinuation { catalogueWaiter = $0 }
    }
    func waitForSettingsRead() async {
        if settingsStarted { return }
        await withCheckedContinuation { settingsWaiter = $0 }
    }
    func finishCatalogueRead() { catalogueContinuation?.resume(); catalogueContinuation = nil }
    func finishSettingsRead() { settingsContinuation?.resume(); settingsContinuation = nil }

    func codexModels(from serverURL: URL, hostId: String) async throws -> CodexModelCatalog {
        catalogueReadCount += 1
        if hostId == suspendedHost {
            await withCheckedContinuation { continuation in
                catalogueContinuation = continuation
                catalogueStarted = true
                catalogueWaiter?.resume()
                catalogueWaiter = nil
            }
        }
        if catalogueFails { throw URLError(.cannotConnectToHost) }
        return catalogueOverride ?? Self.catalogue(host: hostId)
    }

    func codexModelSettings(from serverURL: URL, hostId: String, threadId: String) async throws -> CodexThreadModelSettings {
        settingsReadCount += 1
        if threadId == suspendedThread {
            await withCheckedContinuation { continuation in
                settingsContinuation = continuation
                settingsStarted = true
                settingsWaiter?.resume()
                settingsWaiter = nil
            }
        }
        if settingsFails { throw URLError(.cannotConnectToHost) }
        return settingsOverride ?? CodexThreadModelSettings(hostId: hostId, threadId: threadId,
            model: "model-a", reasoningEffort: "high", observedAt: "2026-10-16T12:00:00Z")
    }

    static func catalogue(host: String, expiresAfter: TimeInterval = 300, observedAt: Date = ModelSettingsNetworkFixture.observedAt,
                          inputModalities: [String] = ["text", "image"]) -> CodexModelCatalog {
        let formatter = ISO8601DateFormatter()
        return CodexModelCatalog(hostId: host, status: "available", source: "local-app-server",
            observedAt: formatter.string(from: observedAt), expiresAt: formatter.string(from: observedAt.addingTimeInterval(expiresAfter)),
            models: [CodexAvailableModel(id: "model-a-id", model: "model-a", displayName: "Model A", description: "Test model",
                supportedReasoningEfforts: [CodexReasoningOption(reasoningEffort: "high", description: "High reasoning")],
                defaultReasoningEffort: "high", inputModalities: inputModalities, isDefault: true)], reason: nil)
    }
}

import XCTest

final class CodexDiagnosticsTests: XCTestCase {
    @MainActor
    func testUnsupportedProtocolAndWrongTargetNeverPublishDiagnostics() async {
        let network = DiagnosticsFixture()
        let model = CodexDiagnosticsModel(network: network)
        let target = CodexChatTarget(thread: CodexThread(id: "chat", title: "Chat", cwd: "/project", updatedAt: 0),
            serverURL: URL(string: "http://bridge.invalid/device/test")!,
            host: CodexHost(id: "local", name: "Mac", kind: "local", configured: true, available: true, reason: nil))
        await network.configure(version: 999, hostID: "local")
        await model.load(for: target)
        XCTAssertNil(model.diagnostics)
        XCTAssertTrue(model.error?.contains("incompatible") == true)
        await network.configure(version: 1, hostID: "another-host")
        await model.load(for: target)
        XCTAssertNil(model.diagnostics)
        XCTAssertNotNil(model.error)
        await network.configure(version: 1, hostID: "local")
        await model.load(for: target)
        XCTAssertEqual(model.diagnostics?.threadId, "chat")
        XCTAssertNil(model.error)
    }
}

private actor DiagnosticsFixture: CodexDiagnosticsNetworking {
    private var version = 1
    private var hostID = "local"
    func configure(version: Int, hostID: String) { self.version = version; self.hostID = hostID }
    func bridgeDiagnostics(for key: CodexConversationKey) async throws -> CodexBridgeDiagnostics {
        CodexBridgeDiagnostics(version: version, observedAt: "2026-10-17T01:00:00Z", hostId: hostID, threadId: key.threadId,
            app: .init(version: "1", build: "1", commit: nil, evidence: "client_reported"),
            mcp: .init(version: "1", buildCommit: nil, sourceCommit: nil, sourceDirty: nil),
            desktop: .init(version: "1", build: "1", asarSha256: nil, artifactPath: "~/ChatGPT.app"), executables: [:],
            compatibility: .init(state: "unverified", reason: nil, evidence: "installed_artifact",
                baseline: .init(desktopVersion: "1", desktopBuild: "1", bundledCliVersion: "1", asarSha256: "digest", inspectedAt: "date", protocol: [:])),
            host: .init(probe: .init(status: "unavailable", operations: nil, revision: nil, code: "desktop_unavailable", outcome: "not_sent", handlingLocation: "desktop"),
                modelCatalog: .init(status: "unavailable", source: nil, observedAt: nil, expiresAt: nil, reason: nil), execution: [:]))
    }
}

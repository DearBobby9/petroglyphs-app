import Foundation

struct CodexBridgeDiagnostics: Codable {
    let version: Int
    let observedAt: String
    let hostId: String
    let threadId: String
    let app: AppInfo
    let mcp: MCPInfo
    let desktop: DesktopInfo
    let executables: [String: Executable]
    let compatibility: Compatibility
    let host: HostInfo

    struct AppInfo: Codable { let version: String?; let build: String?; let commit: String?; let evidence: String }
    struct MCPInfo: Codable { let version: String?; let buildCommit: String?; let sourceCommit: String?; let sourceDirty: Bool? }
    struct DesktopInfo: Codable { let version: String?; let build: String?; let asarSha256: String?; let artifactPath: String }
    struct Executable: Codable { let path: String; let resolvedPath: String?; let version: String? }
    struct Compatibility: Codable {
        let state: String
        let reason: String?
        let evidence: String
        let baseline: Baseline
    }
    struct Baseline: Codable {
        let desktopVersion: String
        let desktopBuild: String
        let bundledCliVersion: String
        let asarSha256: String
        let inspectedAt: String
        let `protocol`: [String: Int]
    }
    struct HostInfo: Codable {
        let probe: Probe
        let modelCatalog: ModelCatalog
        let execution: [String: String]
    }
    struct Probe: Codable {
        let status: String
        let operations: [String]?
        let revision: Int?
        let code: String?
        let outcome: String?
        let handlingLocation: String?
    }
    struct ModelCatalog: Codable {
        let status: String
        let source: String?
        let observedAt: String?
        let expiresAt: String?
        let reason: String?
    }

    var formattedJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

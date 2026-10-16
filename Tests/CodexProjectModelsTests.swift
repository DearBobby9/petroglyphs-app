import XCTest

final class CodexProjectModelsTests: XCTestCase {
    @MainActor
    func testLateProjectListCannotReplaceAnotherHostAndMismatchedResponsesAreRejected() async {
        let network = ProjectNetworkFixture()
        await network.suspendProjects(host: "remote")
        let model = CodexProjectListModel(network: network)
        let old = Task { await model.load(from: server, hostId: "remote") }
        await network.waitForProjectRead()
        await model.load(from: server, hostId: "local")
        await network.finishProjectRead()
        await old.value
        XCTAssertEqual(model.hostId, "local")
        XCTAssertEqual(model.projects.first?.id, "project-local")

        await network.returnWrongProjectHost()
        await model.load(from: server, hostId: "local")
        XCTAssertTrue(model.projects.isEmpty)
        XCTAssertNotNil(model.error)
    }

    @MainActor
    func testLatePaginationCannotAppendChatsFromPreviousProject() async {
        let network = ProjectNetworkFixture()
        let model = CodexThreadListModel(network: network)
        await model.load(from: server, hostId: "local", projectId: "first", search: "", debounce: false)
        await network.suspendPagination()
        let loading = Task { await model.loadMore() }
        await network.waitForPaginationRead()
        await model.load(from: server, hostId: "local", projectId: "second", search: "", debounce: false)
        await network.finishPaginationRead()
        await loading.value
        XCTAssertEqual(model.threads.map(\.id), ["second-chat"])
        XCTAssertEqual(model.projectId, "second")
        XCTAssertFalse(model.isLoadingMore)
    }

    @MainActor
    func testLostCreateResponseSurvivesRestartAndOnlyReadsOriginalRequest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "Remember this first message"
        model.title = "Test project chat"
        await model.submit()
        let original = try XCTUnwrap(model.request)
        XCTAssertNil(model.createdThread)
        XCTAssertFalse(model.canSubmit)
        let restored = creation(network, root: root)
        XCTAssertEqual(restored.request, original)
        XCTAssertEqual(restored.prompt, "Remember this first message")

        let anotherHost = creation(network, root: root, host: "remote")
        let anotherProject = creation(network, root: root, projectID: "another-project")
        let anotherServer = creation(network, root: root, base: URL(string: "http://other.invalid/device/paired")!)
        XCTAssertNil(anotherHost.request)
        XCTAssertNil(anotherProject.request)
        XCTAssertNil(anotherServer.request)

        await network.configure(post: .completed, receipt: .completed)
        await restored.checkStatus()
        await restored.checkStatus()
        let posts = await network.posts
        XCTAssertEqual(posts, [original], "Restoring and checking must not repeat a create POST.")
        XCTAssertEqual(restored.createdThread?.id, "created-chat")
        restored.acknowledgeCompletion()
        XCTAssertNil(creation(network, root: root).request)
    }

    @MainActor
    func testDoubleTapAndStatusReadCannotRaceAnInFlightCreate() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .suspended, receipt: .missing)
        let model = creation(network, root: root)
        model.prompt = "   "
        await model.submit()
        let emptyCount = await network.posts.count
        XCTAssertEqual(emptyCount, 0, "Creating a chat requires an explicit first message.")
        model.prompt = "Start once"
        let creating = Task { await model.submit() }
        await network.waitForPost()
        await model.submit()
        await model.checkStatus()
        let posts = await network.posts
        let reads = await network.receiptReadCount
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(reads, 0, "A GET must not outrun an unresolved POST and offer a duplicate retry.")
        await network.finishPost()
        await creating.value
        XCTAssertEqual(model.createdThread?.id, "created-chat")
    }

    @MainActor
    func testConfirmedMissingRetryKeepsOriginalIDPromptAndProject() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .missing)
        let model = creation(network, root: root)
        model.title = "Original title"
        model.prompt = "Original first message"
        await model.submit()
        XCTAssertTrue(model.canRetryOriginal)
        let original = try XCTUnwrap(model.request)
        model.title = "Changed title"
        model.prompt = "Changed message"
        await network.configure(post: .completed, receipt: .completed)
        await model.retryOriginal()
        let posts = await network.posts
        XCTAssertEqual(posts, [original, original])
        XCTAssertEqual(model.createdThread?.id, "created-chat")
    }

    @MainActor
    func testCreationReceiptFromAnotherTargetCannotSelectAChat() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .wrongTarget, receipt: .wrongTarget)
        let model = creation(network, root: root)
        model.prompt = "A message for this project"
        await model.submit()
        XCTAssertNil(model.createdThread)
        XCTAssertNotNil(model.error)
        XCTAssertNotNil(model.request)
        XCTAssertFalse(model.canSubmit)
    }

    @MainActor
    func testConfirmedFailureRequiresExplicitEditingAndAnotherStartBeforeANewRequest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .failed, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "First attempt"
        await model.submit()
        let originalID = try XCTUnwrap(model.request?.id)
        XCTAssertTrue(model.canEditFailedAttempt)
        model.editFailedAttempt()
        let postsBeforeAnotherStart = await network.posts.count
        XCTAssertEqual(postsBeforeAnotherStart, 1, "Editing must not send a replacement request.")
        XCTAssertNil(model.request)
        XCTAssertNil(creation(network, root: root).request)
        model.prompt = "Revised message"
        await network.configure(post: .completed, receipt: .completed)
        await model.submit()
        let posts = await network.posts
        XCTAssertEqual(posts.count, 2)
        XCTAssertNotEqual(posts[1].id, originalID)
        XCTAssertEqual(posts[1].prompt, "Revised message")
    }

    private var server: URL { URL(string: "http://test.invalid/device/paired")! }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @MainActor
    private func creation(_ network: ProjectNetworkFixture, root: URL, host: String = "local", projectID: String = "project-local", base: URL? = nil) -> CodexProjectCreationModel {
        CodexProjectCreationModel(
            project: CodexProject(id: projectID, name: "Project", path: "/project", canCreate: true, reason: nil),
            host: CodexHost(id: host, name: host, kind: host == "local" ? "local" : "remote", configured: true, available: true, reason: nil),
            serverURL: base ?? server, network: network, storageRoot: root)
    }
}

private actor ProjectNetworkFixture: CodexProjectNetworking, CodexThreadListNetworking {
    enum PostMode { case completed, timeout, suspended, wrongTarget, failed }
    enum ReceiptMode { case completed, unknown, missing, wrongTarget }
    private var postMode = PostMode.completed
    private var receiptMode = ReceiptMode.completed
    private(set) var posts: [CodexCreateChatRequest] = []
    private(set) var receiptReadCount = 0
    private var postWaiter: CheckedContinuation<Void, Never>?
    private var suspendedPost: CheckedContinuation<CodexChatCreationReceipt, Error>?
    private var suspendedProjectHost: String?
    private var projectWaiter: CheckedContinuation<Void, Never>?
    private var projectRead: CheckedContinuation<CodexProjectList, Never>?
    private var wrongProjectHost = false
    private var shouldSuspendPagination = false
    private var paginationWaiter: CheckedContinuation<Void, Never>?
    private var paginationRead: CheckedContinuation<CodexThreadPage, Never>?

    func configure(post: PostMode, receipt: ReceiptMode) { postMode = post; receiptMode = receipt }
    func suspendProjects(host: String) { suspendedProjectHost = host }
    func returnWrongProjectHost() { wrongProjectHost = true }
    func suspendPagination() { shouldSuspendPagination = true }

    func waitForPost() async {
        if suspendedPost != nil { return }
        await withCheckedContinuation { postWaiter = $0 }
    }

    func finishPost() {
        guard let request = posts.last else { return }
        suspendedPost?.resume(returning: receipt(request, state: .completed))
        suspendedPost = nil
    }

    func waitForProjectRead() async {
        if projectRead != nil { return }
        await withCheckedContinuation { projectWaiter = $0 }
    }

    func finishProjectRead() {
        projectRead?.resume(returning: projectList(suspendedProjectHost ?? "remote"))
        projectRead = nil
    }

    func waitForPaginationRead() async {
        if paginationRead != nil { return }
        await withCheckedContinuation { paginationWaiter = $0 }
    }

    func finishPaginationRead() {
        paginationRead?.resume(returning: CodexThreadPage(threads: [thread("old-page-chat")], nextCursor: nil))
        paginationRead = nil
    }

    func codexProjects(from serverURL: URL, hostId: String) async throws -> CodexProjectList {
        if hostId == suspendedProjectHost {
            return await withCheckedContinuation {
                projectRead = $0
                projectWaiter?.resume()
                projectWaiter = nil
            }
        }
        return projectList(wrongProjectHost ? "wrong-host" : hostId)
    }

    func codexThreads(from serverURL: URL, hostId: String, search: String, cursor: String?) async throws -> CodexThreadPage {
        CodexThreadPage(threads: [thread("all-chat")], nextCursor: nil)
    }

    func codexProjectThreads(from serverURL: URL, hostId: String, projectId: String, search: String, cursor: String?) async throws -> CodexThreadPage {
        if cursor != nil && shouldSuspendPagination {
            return await withCheckedContinuation {
                paginationRead = $0
                paginationWaiter?.resume()
                paginationWaiter = nil
            }
        }
        return CodexThreadPage(threads: [thread("\(projectId)-chat")], nextCursor: "next")
    }

    func createCodexChat(_ body: CodexCreateChatRequest, from serverURL: URL) async throws -> CodexChatCreationReceipt {
        posts.append(body)
        switch postMode {
        case .completed: return receipt(body, state: .completed)
        case .wrongTarget: return receipt(body, state: .completed, wrongHost: true)
        case .failed: return receipt(body, state: .failed)
        case .timeout: throw URLError(.timedOut)
        case .suspended:
            return try await withCheckedThrowingContinuation {
                suspendedPost = $0
                postWaiter?.resume()
                postWaiter = nil
            }
        }
    }

    func codexChatCreation(_ body: CodexCreateChatRequest, from serverURL: URL) async throws -> CodexChatCreationReceipt {
        receiptReadCount += 1
        switch receiptMode {
        case .completed: return receipt(body, state: .completed)
        case .unknown: return receipt(body, state: .unknown)
        case .wrongTarget: return receipt(body, state: .completed, wrongHost: true)
        case .missing: throw NetworkService.NetworkError.server(statusCode: 404, message: "Request not found")
        }
    }

    private func receipt(_ request: CodexCreateChatRequest, state: CodexChatCreationState, wrongHost: Bool = false) -> CodexChatCreationReceipt {
        CodexChatCreationReceipt(id: request.id, hostId: wrongHost ? "wrong-host" : request.hostId,
                                 projectId: request.projectId, state: state,
                                 thread: state == .completed ? thread("created-chat") : nil, error: nil, notice: nil)
    }

    private func projectList(_ host: String) -> CodexProjectList {
        CodexProjectList(hostId: host, projects: [CodexProject(id: "project-\(host)", name: host, path: "/project", canCreate: true, reason: nil)])
    }

    private func thread(_ id: String) -> CodexThread { CodexThread(id: id, title: id, cwd: "/project", updatedAt: 1) }
}

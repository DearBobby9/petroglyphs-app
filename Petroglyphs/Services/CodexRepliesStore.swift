import Foundation
import Observation

@MainActor
@Observable
class CodexRepliesStore {
    private(set) var replies: [CodexReply] = []
    private(set) var pollingGeneration = 0
    private(set) var isRecovering = false
    private(set) var recoveryTarget: CodexChatTarget?
    private(set) var recoveryError: String?
    private var recoveryRequestID = UUID()
    private let network = NetworkService()

    var activeCount: Int { replies.filter(\.needsUpdates).count }

    func record(_ receipt: SubmissionResponse, payload: SubmissionPayload, target: CodexChatTarget) {
        guard !replies.contains(where: { $0.id == receipt.id && $0.serverURL == target.serverURL && $0.hostId == target.host.id }) else { return }
        var reply = CodexReply(
            id: receipt.id,
            threadId: target.thread.id,
            hostId: target.host.id,
            hostName: target.host.name,
            chatTitle: target.thread.displayTitle,
            serverURL: target.serverURL,
            imageData: Data(base64Encoded: payload.image),
            sentAt: Date()
        )
        if receipt.threadId != reply.threadId || receipt.hostId != reply.hostId {
            reply.updateError = "The reply receipt does not match this chat. Updates stopped."
            reply.updatesPaused = true
            reply.canRetryUpdates = false
        }
        replies.insert(reply, at: 0)
        pollingGeneration += 1
    }

    func retryUpdates(for reply: CodexReply) {
        guard let index = replies.firstIndex(where: { $0.identity == reply.identity }),
              replies[index].canRetryUpdates else { return }
        prepareStatusRead(at: index)
        pollingGeneration += 1
    }

    func restoreRecentReplies(for target: CodexChatTarget) async {
        let requestID = UUID()
        recoveryRequestID = requestID
        recoveryTarget = target
        recoveryError = nil
        isRecovering = true
        defer {
            if recoveryRequestID == requestID { isRecovering = false }
        }

        let known = replies.indices.filter {
            replies[$0].serverURL == target.serverURL && replies[$0].hostId == target.host.id && replies[$0].threadId == target.thread.id
        }
        for index in known { prepareStatusRead(at: index) }
        if !known.isEmpty { pollingGeneration += 1 }

        do {
            let recent = try await network.recentCodexSubmissions(threadId: target.thread.id, hostId: target.host.id, from: target.serverURL)
            guard !Task.isCancelled, recoveryRequestID == requestID else { return }
            guard recent.allSatisfy({ $0.threadId == target.thread.id && $0.hostId == target.host.id }) else {
                recoveryError = "The server returned submissions for a different chat. No records were restored."
                return
            }
            var added = false
            for submission in recent {
                if replies.contains(where: { $0.id == submission.id && $0.serverURL == target.serverURL && $0.hostId == target.host.id }) { continue }
                replies.append(CodexReply(
                    id: submission.id,
                    threadId: submission.threadId,
                    hostId: submission.hostId,
                    hostName: target.host.name,
                    chatTitle: target.thread.displayTitle,
                    serverURL: target.serverURL,
                    imageData: nil,
                    sentAt: submission.createdAt,
                    state: .unknown,
                    needsStatusRefresh: true
                ))
                added = true
            }
            if added {
                replies.sort { $0.sentAt > $1.sentAt }
                pollingGeneration += 1
            }
        } catch {
            guard !Task.isCancelled, recoveryRequestID == requestID else { return }
            recoveryError = error.localizedDescription
        }
    }

    private func prepareStatusRead(at index: Int) {
        replies[index].needsStatusRefresh = true
        replies[index].refreshVersion += 1
        replies[index].updatesPaused = false
        replies[index].canRetryUpdates = true
        replies[index].updateError = nil
        replies[index].failedReads = 0
        replies[index].unchangedReads = 0
        replies[index].nextPollAt = Date()
    }

    // The canvas owns this task, so leaving the screen or backgrounding the app cancels reads.
    func pollPendingReplies() async {
        while !Task.isCancelled {
            guard let next = replies.filter(\.needsUpdates).min(by: { $0.nextPollAt < $1.nextPollAt }) else { return }
            let delay = next.nextPollAt.timeIntervalSinceNow
            if delay > 0 {
                do { try await Task.sleep(for: .seconds(min(delay, 24))) }
                catch { return }
                continue
            }
            await refresh(next)
        }
    }

    private func refresh(_ snapshot: CodexReply) async {
        do {
            let status = try await network.codexSubmission(snapshot.id, hostId: snapshot.hostId, from: snapshot.serverURL)
            guard !Task.isCancelled, let index = replies.firstIndex(where: { $0.identity == snapshot.identity }),
                  replies[index].refreshVersion == snapshot.refreshVersion else { return }
            guard status.id == snapshot.id, status.threadId == snapshot.threadId, status.hostId == snapshot.hostId else {
                replies[index].updateError = "The server returned a reply for a different destination. Updates stopped."
                replies[index].updatesPaused = true
                replies[index].canRetryUpdates = false
                return
            }

            let changed = replies[index].state != status.state || replies[index].messages != status.messages
            replies[index].state = status.state
            replies[index].messages = status.messages
            replies[index].error = status.error
            replies[index].notice = status.notice
            replies[index].updateError = nil
            replies[index].failedReads = 0
            replies[index].needsStatusRefresh = false
            let delay = changed ? 3 : 3 * pow(2, Double(replies[index].unchangedReads))
            replies[index].unchangedReads = changed ? 0 : min(replies[index].unchangedReads + 1, 2)
            replies[index].nextPollAt = Date().addingTimeInterval(delay)
        } catch {
            guard !Task.isCancelled, let index = replies.firstIndex(where: { $0.identity == snapshot.identity }),
                  replies[index].refreshVersion == snapshot.refreshVersion else { return }
            replies[index].failedReads += 1
            replies[index].updateError = error.localizedDescription
            if case NetworkService.NetworkError.server(let statusCode, _) = error,
               (400..<500).contains(statusCode), statusCode != 408, statusCode != 429 {
                replies[index].updatesPaused = true
                replies[index].canRetryUpdates = false
            } else {
                replies[index].updatesPaused = replies[index].failedReads >= 5
                let delay = min(3 * pow(2, Double(replies[index].failedReads - 1)), 24)
                replies[index].nextPollAt = Date().addingTimeInterval(delay)
            }
        }
    }
}

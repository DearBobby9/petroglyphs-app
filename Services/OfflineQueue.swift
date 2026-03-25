import Foundation

@Observable
class OfflineQueue {
    private(set) var pending: [SubmissionPayload] = []
    private let maxSize = 5
    private let network = NetworkService()

    func enqueue(_ payload: SubmissionPayload) {
        if pending.count >= maxSize { pending.removeFirst() }
        pending.append(payload)
    }

    func drain(to serverURL: URL) {
        let items = pending
        pending = []
        Task {
            for item in items {
                try? await network.submit(item, to: serverURL)
            }
        }
    }
}

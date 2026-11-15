import Foundation
import Observation

/// All messages in the project (the backend's unfiltered oversight view), kept current by activity events.
@MainActor @Observable
final class MessagesModel {
    private(set) var messages: [HiveMessage] = []
    private(set) var phase: LoadPhase = .idle
    private(set) var isSending = false

    @ObservationIgnored private var context: DataContext?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshQueued = false

    private static let pageSize = 500
    private static let maxPages = 20

    func bind(_ context: DataContext) {
        reset()
        self.context = context
    }

    func reset() {
        context = nil
        messages = []
        phase = .idle
        isSending = false
        refreshQueued = false
    }

    func loadIfNeeded() async {
        guard phase == .idle else { return }
        await reload()
    }

    func reload() async {
        guard let context else { return }
        phase = .loading
        do {
            messages = try await Self.fetch(after: 0, context: context)
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Fetches only messages newer than the ones already held. Safe to call often.
    func refresh() async {
        guard phase == .loaded, let context else { return }
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshQueued = false
            if let fresh = try? await Self.fetch(after: messages.last?.seq ?? 0, context: context) {
                merge(fresh)
            }
        } while refreshQueued
    }

    @discardableResult
    func send(_ draft: NewMessageDraft) async throws -> HiveMessage {
        guard let context else { throw HiveBackendError.serviceUnavailable("No project is open.") }
        isSending = true
        defer { isSending = false }
        let sent = try await context.dataSource.sendMessage(for: context.project, draft: draft)
        merge([sent])
        return sent
    }

    private func merge(_ incoming: [HiveMessage]) {
        guard !incoming.isEmpty else { return }
        var bySeq = Dictionary(uniqueKeysWithValues: messages.map { ($0.seq, $0) })
        for message in incoming { bySeq[message.seq] = message }
        messages = bySeq.values.sorted { $0.seq < $1.seq }
    }

    private static func fetch(after: Int, context: DataContext) async throws -> [HiveMessage] {
        var result: [HiveMessage] = []
        var cursor = after
        for _ in 0..<maxPages {
            let page = try await context.dataSource.messages(for: context.project, afterSeq: cursor, limit: pageSize)
            result += page
            guard page.count == pageSize, let last = page.last else { break }
            cursor = last.seq
        }
        return result
    }
}

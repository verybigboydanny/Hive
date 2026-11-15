import Foundation
import Observation

/// The audit log: the newest events from the backend, extended live as events arrive.
@MainActor @Observable
final class ActivityModel {
    /// Newest first.
    private(set) var events: [ActivityEvent] = []
    private(set) var phase: LoadPhase = .idle

    @ObservationIgnored private var context: DataContext?

    static let historyLimit = 500
    private static let keepLimit = 2_000

    func bind(_ context: DataContext) {
        reset()
        self.context = context
    }

    func reset() {
        context = nil
        events = []
        phase = .idle
    }

    func loadIfNeeded() async {
        guard phase == .idle else { return }
        await reload()
    }

    func reload() async {
        guard let context else { return }
        if phase != .loaded { phase = .loading }
        do {
            let fetched = try await context.dataSource.activity(for: context.project, afterID: nil, limit: Self.historyLimit)
            merge(fetched)
            phase = .loaded
        } catch {
            if phase == .loaded { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Live events from the session's poller are added directly; no extra request.
    func receive(_ event: ActivityEvent) {
        merge([event])
    }

    /// Events that arrived through a snapshot reload.
    func receive(contentsOf events: [ActivityEvent]) {
        merge(events)
    }

    private func merge(_ incoming: [ActivityEvent]) {
        guard !incoming.isEmpty else { return }
        var byCursor = Dictionary(events.map { ($0.cursor, $0) }, uniquingKeysWith: { first, _ in first })
        for event in incoming { byCursor[event.cursor] = event }
        let sorted = byCursor.values.sorted { $0.cursor > $1.cursor }
        events = Array(sorted.prefix(Self.keepLimit))
    }
}

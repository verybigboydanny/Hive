import Foundation
import Observation

/// Handoffs of every status (the Dashboard only needs the pending ones).
@MainActor @Observable
final class HandoffsModel {
    private(set) var handoffs: [Handoff] = []
    private(set) var phase: LoadPhase = .idle

    @ObservationIgnored private var context: DataContext?

    func bind(_ context: DataContext) {
        reset()
        self.context = context
    }

    func reset() {
        context = nil
        handoffs = []
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
            handoffs = try await context.dataSource.handoffs(for: context.project)
            phase = .loaded
        } catch {
            if phase == .loaded { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Called when a handoff event arrives.
    func refresh() async {
        guard phase == .loaded else { return }
        await reload()
    }
}

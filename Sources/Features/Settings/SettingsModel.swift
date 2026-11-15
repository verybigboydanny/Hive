import Foundation
import Observation

/// What the Settings window reads from the backend. Settings is app-level (not tied to one project window),
/// so it reads whichever workspace the local API currently has open.
@MainActor @Observable
final class SettingsModel {
    private(set) var phase: LoadPhase = .idle
    private(set) var health: BackendHealth?
    private(set) var healthError: String?
    private(set) var workspace: WorkspaceInfo?
    private(set) var context: ProjectContext?
    private(set) var contextError: String?

    let dataSource: any HiveDataSource

    init(dataSource: any HiveDataSource) {
        self.dataSource = dataSource
    }

    var isPreviewData: Bool { dataSource.isPreviewData }

    func load() async {
        phase = .loading
        do {
            health = try await dataSource.backendHealth()
            healthError = nil
        } catch {
            health = nil
            healthError = error.localizedDescription
        }
        do {
            workspace = try await dataSource.currentWorkspace()
            context = try await dataSource.currentContext()
            contextError = nil
        } catch {
            workspace = nil
            context = nil
            contextError = error.localizedDescription
        }
        phase = .loaded
    }
}

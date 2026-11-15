import SwiftUI
import AppKit

/// The state of the local Hive backend. Read-only: the app starts and configures it itself.
struct BackendSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage(
            title: "Backend",
            subtitle: "Hive keeps all project data in a local backend that the app starts for you."
        ) {
            ReadOnlyNotice(message: "The app starts and configures the backend itself, and the API has no endpoints for changing its settings, so there is nothing to edit here.")

            if model.isPreviewData {
                Label("This copy of Hive is showing preview data, not a real backend.", systemImage: "flask")
                    .foregroundStyle(.orange)
            }

            if let health = model.health {
                BackendHealthView(health: health)
            } else if let message = model.healthError {
                BackendErrorView(message: message)
            } else {
                ProgressView("Checking the backend…")
            }

            HStack {
                Button("Check Again", systemImage: "arrow.clockwise") {
                    Task { await model.load() }
                }
                Button("Show Bundled Backend in Finder", systemImage: "folder") {
                    revealBundledBackend()
                }
            }

            BackendHowItWorksView()
        }
    }

    private func revealBundledBackend() {
        guard let url = Bundle.main.resourceURL?.appending(path: "hive-backend") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

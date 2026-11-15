import SwiftUI

/// Shown on settings pages that describe the open project when none is open.
struct NoProjectNotice: View {
    let model: SettingsModel

    var body: some View {
        ContentUnavailableView {
            Label("No Project Open", systemImage: "folder")
        } description: {
            Text("Open a project in the Hive window, then check again.")
        } actions: {
            Button("Check Again") {
                Task { await model.load() }
            }
        }
    }
}

import SwiftUI

/// Shown where agents would be listed when none have connected yet.
struct ConnectAgentRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
            Text("No agents have connected yet.")
                .foregroundStyle(.secondary)
            SettingsLink {
                Label("Connect Claude…", systemImage: "link")
            }
        }
    }
}

import SwiftUI

struct WorkspaceView: View {
    @Environment(ProjectSession.self) private var session

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: HiveMetrics.sidebarMinWidth,
                    ideal: HiveMetrics.sidebarIdealWidth,
                    max: HiveMetrics.sidebarMaxWidth
                )
        } detail: {
            WorkspaceDetailView()
        }
        .navigationTitle(session.project?.name ?? "Hive")
        .navigationSubtitle(session.project?.rootURL.path(percentEncoded: false) ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await session.reloadAll() }
                }
                .help("Refresh project data")
            }
        }
    }
}

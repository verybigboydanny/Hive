import SwiftUI

struct WorkspaceDetailView: View {
    @Environment(ProjectSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch session.selection {
            case .dashboard: DashboardView()
            case .files: FilesView()
            case .agents: AgentsView()
            case .setUpAgent: SetUpAgentView()
            case .tasks: TasksView()
            case .messages: MessagesView()
            case .activity: ActivityView()
            case .guide: HowToUseHiveView()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.99)))
        .animation(
            reduceMotion ? .easeOut(duration: 0.1) : .snappy(duration: 0.26),
            value: session.selection
        )
        .scrollContentBackground(.hidden)
        .background { HiveAmbientBackground() }
    }
}

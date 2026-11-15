import SwiftUI

struct ProjectHeader: View {
    let project: HiveProject
    let overview: ProjectOverview
    let isPreviewData: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                Text(project.name)
                    .font(.title2.bold())
                Text(project.rootURL.path(percentEncoded: false))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let git = overview.git {
                    GitSummaryLabel(git: git)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                StatusIndicator(title: project.status.title, color: project.status.color)
                if isPreviewData {
                    Text("Using preview data")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

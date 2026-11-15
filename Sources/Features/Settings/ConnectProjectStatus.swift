import SwiftUI

/// Which project the commands below are written for.
struct ConnectProjectStatus: View {
    let model: SettingsModel
    let usesCustomFolder: Bool

    var body: some View {
        Group {
            if usesCustomFolder {
                Label("Using the project folder you typed under Customize.", systemImage: "folder")
            } else if let workspace = model.workspace {
                Label {
                    VStack(alignment: .leading) {
                        Text(workspace.name)
                            .bold()
                        Text(workspace.root)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } icon: {
                    Image(systemName: "folder.fill")
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                        Text("No project is open")
                            .bold()
                        Text("Open a project in the Hive window and its folder is filled in here. Until then the examples use a placeholder path that you must replace.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Check Again") {
                            Task { await model.load() }
                        }
                    }
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .padding(HiveMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: HiveMetrics.cardRadius))
    }
}

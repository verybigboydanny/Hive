import SwiftUI

struct BackendHealthView: View {
    let health: BackendHealth

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingLoose) {
            Form {
                Section("Local API") {
                    LabeledContent("Status") {
                        StatusIndicator(title: health.apiStatus == "ok" ? "Running" : "Not healthy", color: health.apiStatus == "ok" ? .green : .orange)
                    }
                    LabeledContent("Running For") {
                        Text(Duration.seconds(health.apiUptimeSeconds), format: .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
                    }
                    if let version = health.backendVersion {
                        LabeledContent("Backend Version", value: version)
                    }
                    if let version = health.contractVersion {
                        LabeledContent("Contract Version", value: version)
                    }
                    if let pid = health.processID {
                        LabeledContent("Process ID", value: String(pid))
                    }
                }
                Section("Open Project") {
                    if health.workspaceOpen {
                        LabeledContent("Status") {
                            StatusIndicator(title: health.workspaceStatus == "ok" ? "Healthy" : "Needs attention", color: health.workspaceStatus == "ok" ? .green : .orange)
                        }
                        if let ok = health.databaseOK {
                            LabeledContent("Database", value: ok ? "OK" : "Problem")
                        }
                        if let version = health.schemaVersion, let expected = health.expectedSchemaVersion {
                            LabeledContent("Schema Version", value: version == expected ? "\(version)" : "\(version) (expected \(expected))")
                        }
                        if let ok = health.workspaceFoldersOK {
                            LabeledContent("Project Folders", value: ok ? "OK" : "Problem")
                        }
                    } else {
                        Text("No project is open.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !health.stats.isEmpty {
                    Section("Counts") {
                        ForEach(health.stats.keys.sorted(), id: \.self) { key in
                            LabeledContent {
                                Text(health.stats[key] ?? 0, format: .number)
                            } label: {
                                Text(verbatim: key.replacingOccurrences(of: "_", with: " ").capitalized)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .hiveGroupedBackground()
            .scrollDisabled(true)
        }
    }
}

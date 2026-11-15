import SwiftUI

/// What agents may do, and the limits Hive enforces. All of it is read-only.
struct PermissionsSettingsView: View {
    var body: some View {
        SettingsPage(
            title: "Permissions",
            subtitle: "How Hive keeps several agents from getting in each other's way."
        ) {
            ReadOnlyNotice(message: "Hive has no per-agent permission settings, and its API can neither read nor change these limits. A project can override the limits marked below by adding a `settings` object with whole numbers to `.hive/config.json`. Hive reads it when the project is opened.")

            VStack(alignment: .leading, spacing: HiveMetrics.spacingLoose) {
                ForEach(PermissionsContent.rules) { rule in
                    Label {
                        VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                            Text(rule.title)
                                .bold()
                            Text(rule.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: rule.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Limits")
                .font(.headline)
            Text("Hive's defaults for a new project.")
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(PermissionsContent.limits) { limit in
                    LimitRow(limit: limit)
                    Divider()
                }
            }
        }
    }
}

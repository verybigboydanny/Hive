import SwiftUI

struct LimitRow: View {
    let limit: PermissionsContent.Limit

    var body: some View {
        HStack {
            Text(limit.name)
            if limit.isOverridable {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                    .help("A project can override this in .hive/config.json")
                    .accessibilityLabel("Can be overridden per project")
            }
            Spacer()
            Text(limit.value)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, HiveMetrics.spacing)
        .accessibilityElement(children: .combine)
    }
}

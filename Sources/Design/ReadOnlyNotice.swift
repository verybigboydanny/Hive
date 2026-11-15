import SwiftUI

/// Tells the user a setting can't be changed from the app, and why.
struct ReadOnlyNotice: View {
    let message: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                Text("Read-only")
                    .bold()
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "lock")
                .foregroundStyle(.secondary)
        }
        .padding(HiveMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: HiveMetrics.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

/// A scrolling page with a title, shared by the Settings tabs.
struct SettingsPage<Content: View>: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let content: Content

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HiveMetrics.spacingLoose) {
                VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                    Text(title)
                        .font(.title2.bold())
                    if let subtitle {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HiveMetrics.spacingLoose)
        }
    }
}

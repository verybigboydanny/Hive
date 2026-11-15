import SwiftUI

struct BackendErrorView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
            InlineErrorView(message: message)
            Text("Hive runs its backend with Python 3.11 or later from the copy bundled inside the app. If Python is missing or too old, install a newer one (for example with Homebrew) and check again.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

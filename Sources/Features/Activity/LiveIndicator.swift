import SwiftUI

/// Shows that the log is updating as events arrive.
struct LiveIndicator: View {
    let isPreview: Bool

    var body: some View {
        StatusIndicator(title: isPreview ? "Preview" : "Live", color: .green, pulses: !isPreview)
            .help(isPreview ? "Showing simulated activity" : "New activity appears as it happens")
    }
}

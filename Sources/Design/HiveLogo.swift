import SwiftUI

/// The Hive mark in the current accent, as a vector that scales with `size`.
struct HiveLogo: View {
    var size: Double = HiveMetrics.welcomeLogoSize

    @Environment(\.hiveAccent) private var accent

    var body: some View {
        HiveMark()
            .fill(accent.gradient, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            .shadow(color: accent.color.opacity(0.35), radius: size * 0.16, y: size * 0.04)
            .accessibilityHidden(true)
    }
}

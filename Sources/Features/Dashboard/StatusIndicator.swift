import SwiftUI

/// A colored dot plus a text label, so status never relies on color alone.
struct StatusIndicator: View {
    let title: LocalizedStringKey
    let color: Color
    var pulses = false

    var body: some View {
        Label {
            Text(title)
        } icon: {
            HivePulseDot(color: color, size: HiveMetrics.statusDotSize, isPulsing: pulses)
        }
    }
}

import SwiftUI

struct MessageDayHeader: View {
    let day: Date
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(day, format: .dateTime.weekday(.wide).month().day().year())
            .bold()
            .foregroundStyle(.secondary)
            .padding(.horizontal, HiveMetrics.spacingLoose)
            .padding(.vertical, HiveMetrics.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if colorScheme == .dark {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(HivePanel.wash)
                } else {
                    Rectangle().fill(.bar)
                }
            }
    }
}

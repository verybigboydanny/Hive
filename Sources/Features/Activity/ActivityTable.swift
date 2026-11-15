import SwiftUI

struct ActivityTable: View {
    let events: [ActivityEvent]
    let isFiltering: Bool
    @Binding var selection: ActivityEvent.ID?

    var body: some View {
        Table(events, selection: $selection) {
            TableColumn("Time") { event in
                Text(event.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                    .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 150)
            TableColumn("Who") { event in
                Text(event.agentName ?? "System")
            }
            .width(min: 80, ideal: 110)
            TableColumn("Activity") { event in
                Label(event.summary, systemImage: event.kind.symbol)
            }
        }
        .hiveTableStyle()
        .overlay {
            if events.isEmpty && isFiltering {
                ContentUnavailableView.search
            }
        }
    }
}

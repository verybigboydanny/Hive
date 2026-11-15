import SwiftUI

struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                VStack(alignment: .leading) {
                    Text(event.summary)
                    if let agentName = event.agentName {
                        Text(agentName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: event.kind.symbol)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.timestamp, format: .relative(presentation: .named))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

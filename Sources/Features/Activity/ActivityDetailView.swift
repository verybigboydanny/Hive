import SwiftUI

struct ActivityDetailView: View {
    let event: ActivityEvent
    @Environment(ProjectSession.self) private var session

    var body: some View {
        Form {
            Section {
                Label(event.summary, systemImage: event.kind.symbol)
                    .font(.headline)
                    .textSelection(.enabled)
            }
            .hivePanelRows()

            Section("Event") {
                LabeledContent("When") {
                    Text(event.timestamp, format: .dateTime.month().day().year().hour().minute().second())
                }
                LabeledContent("Who", value: event.agentName ?? "System")
                if let kind = event.actorKind {
                    LabeledContent("Kind", value: kind.capitalized)
                }
                if !event.action.isEmpty {
                    LabeledContent("Action", value: event.action)
                }
                if let type = event.targetType, let id = event.targetID {
                    LabeledContent {
                        ActivityTargetLink(targetType: type, targetID: id)
                    } label: {
                        Text(verbatim: type.capitalized)
                    }
                }
                LabeledContent("Event ID", value: event.id)
            }
            .hivePanelRows()

            if let details = event.detailsJSON {
                Section("Details") {
                    CodeBlock(text: details)
                }
                .hivePanelRows()
            }
        }
        .formStyle(.grouped)
        .hiveGroupedBackground()
    }
}

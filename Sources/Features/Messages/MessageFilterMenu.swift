import SwiftUI

struct MessageFilterMenu: View {
    @Binding var filter: MessageFilter
    @Environment(ProjectSession.self) private var session

    var body: some View {
        Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
            Picker("Type", selection: $filter.kind) {
                Text("All Types").tag(HiveMessage.Kind?.none)
                ForEach(HiveMessage.Kind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(Optional(kind))
                }
            }
            Picker("Participant", selection: $filter.participantID) {
                Text("Everyone").tag(String?.none)
                Text("You").tag(Optional("user"))
                ForEach(session.snapshot?.agents ?? []) { agent in
                    Text(agent.name).tag(Optional(agent.id))
                }
            }
        }
        .help("Filter messages")
    }
}

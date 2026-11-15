import SwiftUI

struct HandoffsView: View {
    @Environment(ProjectSession.self) private var session
    @State private var selection: Handoff.ID?
    @State private var statusFilter: Handoff.Status?

    var body: some View {
        let model = session.handoffs
        switch model.phase {
        case .idle, .loading:
            ProgressView("Loading handoffs…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Handoffs", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await session.handoffs.reload() }
                }
            }
        case .loaded:
            if model.handoffs.isEmpty {
                ContentUnavailableView(
                    "No Handoffs Yet",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("When an agent hands its work to another agent, the handoff appears here.")
                )
            } else {
                let visible = model.handoffs.filter { statusFilter == nil || $0.status == statusFilter }
                HSplitView {
                    VStack(spacing: 0) {
                        Picker("Status", selection: $statusFilter) {
                            Text("All").tag(Handoff.Status?.none)
                            ForEach(Handoff.Status.allCases, id: \.self) { status in
                                Text(status.title).tag(Optional(status))
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(HiveMetrics.spacing)
                        List(visible, selection: $selection) { handoff in
                            HandoffRow(handoff: handoff)
                                .hivePanelRows()
                        }
                        .listStyle(.inset)
                        .hiveGroupedBackground()
                    }
                    .frame(minWidth: HiveMetrics.listPaneMinWidth, idealWidth: HiveMetrics.listPaneIdealWidth)
                    HandoffDetailPane(handoff: model.handoffs.first { $0.id == selection })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

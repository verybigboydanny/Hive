import SwiftUI

/// The project's audit log: what every agent and the user did, newest first.
struct ActivityView: View {
    @Environment(ProjectSession.self) private var session
    @State private var filter = ActivityFilter()
    @State private var selection: ActivityEvent.ID?
    @State private var showsInspector = false

    var body: some View {
        let model = session.activity
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView("Loading activity…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Load Activity", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task { await session.activity.reload() }
                    }
                }
            case .loaded:
                if model.events.isEmpty {
                    ContentUnavailableView(
                        "No Activity Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Everything agents and you do in this project is recorded here.")
                    )
                } else {
                    ActivityTable(events: filter.apply(to: model.events), isFiltering: filter.isFiltering, selection: $selection)
                }
            }
        }
        .searchable(text: $filter.searchText, prompt: "Search activity")
        .toolbar {
            ToolbarItem {
                ActivityFilterMenu(filter: $filter, events: model.events)
            }
            ToolbarItem {
                LiveIndicator(isPreview: session.dataSource.isPreviewData)
            }
        }
        .inspector(isPresented: $showsInspector) {
            ActivityInspector(event: model.events.first { $0.id == selection })
                .inspectorColumnWidth(min: HiveMetrics.inspectorMinWidth, ideal: HiveMetrics.inspectorIdealWidth, max: HiveMetrics.inspectorMaxWidth)
        }
        .onChange(of: selection) {
            showsInspector = selection != nil
        }
        .task {
            await session.activity.loadIfNeeded()
        }
    }
}

import SwiftUI

struct RecentProjectsList: View {
    @Environment(ProjectSession.self) private var session

    var body: some View {
        Group {
            if session.recents.items.isEmpty {
                ContentUnavailableView(
                    "No Recent Projects",
                    systemImage: "clock",
                    description: Text("Projects you open will appear here.")
                )
            } else {
                List {
                    Section("Recent Projects") {
                        ForEach(Array(session.recents.items.enumerated()), id: \.element.id) { index, recent in
                            Button {
                                Task { await session.openRecent(recent) }
                            } label: {
                                RecentProjectRow(recent: recent)
                            }
                            .buttonStyle(.hivePress)
                            .disabled(session.isOpening)
                            .hiveAppear(delay: 0.1 + Double(index) * 0.05)
                            .contextMenu {
                                Button("Remove from Recents") {
                                    session.recents.remove(recent)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

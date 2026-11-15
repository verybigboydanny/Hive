import SwiftUI

struct SummaryStrip: View {
    let snapshot: ProjectSnapshot
    @Environment(\.hiveAccent) private var accent

    var body: some View {
        HiveGlassGroup(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                tile {
                    MetricView(
                        title: "Agents Online",
                        value: snapshot.connectedAgentCount,
                        detail: Text("of \(snapshot.agents.count) connected")
                    )
                }
                .hiveAppear(delay: 0.05)
                tile {
                    MetricView(
                        title: "Active Tasks",
                        value: snapshot.activeTasks.count,
                        detail: Text("\(snapshot.blockedTaskCount) blocked")
                    )
                }
                .hiveAppear(delay: 0.12)
                tile {
                    MetricView(
                        title: "Open Handoffs",
                        value: snapshot.handoffs.count,
                        detail: Text("waiting to be accepted")
                    )
                }
                .hiveAppear(delay: 0.19)
            }
        }
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .hiveGlass(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: accent.isFrosted ? nil : accent.color.opacity(0.10),
                interactive: true
            )
            .hiveHover(scale: 1.025)
    }
}

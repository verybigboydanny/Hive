import SwiftUI

struct DashboardSectionHeader: View {
    let title: LocalizedStringKey
    let destination: SidebarItem
    @Environment(ProjectSession.self) private var session

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button("View All") {
                session.selection = destination
            }
            .buttonStyle(.link)
        }
    }
}

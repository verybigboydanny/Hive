import SwiftUI

struct HandoffDetailPane: View {
    let handoff: Handoff?

    var body: some View {
        if let handoff {
            HandoffDetailView(handoff: handoff)
        } else {
            ContentUnavailableView("Select a Handoff", systemImage: "arrow.left.arrow.right", description: Text("Choose a handoff to read what was done and what is left."))
        }
    }
}

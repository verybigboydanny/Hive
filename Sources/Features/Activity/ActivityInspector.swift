import SwiftUI

struct ActivityInspector: View {
    let event: ActivityEvent?

    var body: some View {
        if let event {
            ActivityDetailView(event: event)
        } else {
            ContentUnavailableView("No Event Selected", systemImage: "clock.arrow.circlepath")
        }
    }
}

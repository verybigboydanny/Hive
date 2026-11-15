import SwiftUI

struct ActivityFilterMenu: View {
    @Binding var filter: ActivityFilter
    let events: [ActivityEvent]

    var body: some View {
        Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
            Picker("Category", selection: $filter.category) {
                ForEach(ActivityCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            Picker("Who", selection: $filter.actorID) {
                Text("Everyone").tag(String?.none)
                ForEach(ActivityActor.actors(in: events)) { actor in
                    Text(actor.name).tag(Optional(actor.id))
                }
            }
        }
        .help("Filter activity")
    }
}

import SwiftUI

struct MessageList: View {
    let messages: [HiveMessage]
    let isFiltering: Bool
    @Binding var composeContext: ComposeContext?

    var body: some View {
        if messages.isEmpty && isFiltering {
            ContentUnavailableView.search
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(MessageDayGroup.groups(from: messages)) { group in
                        Section {
                            ForEach(group.messages) { message in
                                MessageRowView(message: message) {
                                    composeContext = ComposeContext.reply(to: message)
                                }
                                Divider()
                            }
                        } header: {
                            MessageDayHeader(day: group.day)
                        }
                    }
                }
            }
            .defaultScrollAnchor(.bottom)
        }
    }
}

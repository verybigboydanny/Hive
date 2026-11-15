import SwiftUI

struct AttentionRow: View {
    let item: AttentionItem
    let onSelect: @MainActor (AttentionItem) -> Void

    var body: some View {
        Button {
            onSelect(item)
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(item.title)
                    Text(item.detail)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(item.kind.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

struct RecentProjectRow: View {
    let recent: RecentProject

    @Environment(\.hiveAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(recent.name)
                Text(recent.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: isHovering ? "folder.fill" : "folder")
                .foregroundStyle(isHovering ? accent.color : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(accent.color.opacity(isHovering ? 0.12 : 0))
                .padding(.horizontal, -6)
        }
        .offset(x: isHovering && !reduceMotion ? 3 : 0)
        .contentShape(.rect)
        .onHover { hovering in
            withAnimation(HiveMotion.resolved(.easeOut(duration: 0.16), reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
    }
}

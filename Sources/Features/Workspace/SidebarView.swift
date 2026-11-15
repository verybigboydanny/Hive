import SwiftUI

struct SidebarView: View {
    @Environment(ProjectSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hiveAccent) private var accent
    @Namespace private var selectionNamespace
    @State private var hoveredItem: SidebarItem?
    /// Bumped only for the item that has just become selected, so only that icon bounces.
    /// (Keying the effect on `isSelected` would also fire for the item being deselected.)
    @State private var bounceTokens: [SidebarItem: Int] = [:]

    var body: some View {
        List {
            Section("Project") {
                row(for: .dashboard)
                row(for: .files)
            }
            Section("Coordination") {
                row(for: .agents)
                row(for: .setUpAgent)
                row(for: .tasks)
                row(for: .messages)
                row(for: .activity)
            }
            Section("Help") {
                row(for: .guide)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: session.selection) { _, newSelection in
            bounceTokens[newSelection, default: 0] += 1
        }
    }

    private func row(for item: SidebarItem) -> some View {
        let isSelected = session.selection == item

        return Button {
            session.selection = item
        } label: {
            HStack(spacing: 8) {
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.symbol)
                        .foregroundStyle(isSelected ? accent.color : Color.secondary)
                        .symbolEffect(.bounce, options: .nonRepeating, value: bounceTokens[item, default: 0])
                }
                Spacer(minLength: 4)
                let count = badge(for: item)
                if count > 0 {
                    Text(count.formatted())
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(accent.color.opacity(0.16), in: .capsule)
                        .contentTransition(.numericText())
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("\(count) items need attention")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.color.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(accent.color.opacity(0.35), lineWidth: 0.8)
                        }
                        .matchedGeometryEffect(id: "sidebar.selection", in: selectionNamespace)
                } else if hoveredItem == item {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredItem = item
            } else if hoveredItem == item {
                hoveredItem = nil
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.36, dampingFraction: 0.78),
            value: session.selection
        )
        .animation(.easeOut(duration: 0.12), value: hoveredItem)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.\(item.rawValue)")
    }

    /// Counts that call for attention: pending handoffs on Messages, blocked tasks on Tasks.
    private func badge(for item: SidebarItem) -> Int {
        guard let snapshot = session.snapshot else { return 0 }
        switch item {
        case .messages: return snapshot.handoffs.count
        case .tasks: return snapshot.blockedTaskCount
        default: return 0
        }
    }
}

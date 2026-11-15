import SwiftUI

struct TaskCardView: View {
    let task: HiveTask
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hiveAccent) private var accent

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: HiveMetrics.cardRadius + 4, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
            Text(task.title)
                .bold()
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if task.priority >= .high || !task.labels.isEmpty {
                HStack(spacing: HiveMetrics.spacingTight) {
                    if task.priority >= .high {
                        Pill(task.priority.title, tint: task.priority.tint)
                    }
                    ForEach(task.labels.prefix(2), id: \.self) { label in
                        Pill(verbatim: label)
                    }
                }
            }
            if let owner = task.ownerName {
                Label(owner, systemImage: "person")
                    .foregroundStyle(.secondary)
            }
            if task.isLeaseExpired {
                Label("Claim expired", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            } else if !task.blockedBy.isEmpty {
                Label("Waiting on \(task.blockedBy.count)", systemImage: "link")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(HiveMetrics.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hiveGlass(in: shape, tint: isSelected ? accent.color.opacity(0.22) : nil, interactive: true)
        .overlay {
            shape.strokeBorder(accent.color, lineWidth: isSelected ? 2 : 0)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .snappy(duration: 0.18), value: isSelected)
        .hiveHover(scale: 1.015)
        .contentShape(.rect(cornerRadius: HiveMetrics.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

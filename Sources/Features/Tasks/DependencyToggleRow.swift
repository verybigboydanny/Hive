import SwiftUI

struct DependencyToggleRow: View {
    let task: HiveTask
    @Binding var selection: Set<HiveTask.ID>

    var body: some View {
        Toggle(task.title, isOn: isSelected)
    }

    private var isSelected: Binding<Bool> {
        Binding(
            get: { selection.contains(task.id) },
            set: { isOn in
                if isOn {
                    selection.insert(task.id)
                } else {
                    selection.remove(task.id)
                }
            }
        )
    }
}

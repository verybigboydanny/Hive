import SwiftUI

/// All tasks as a board (one column per status) or a sortable list, with an inspector for the selected task.
struct TasksView: View {
    @Environment(ProjectSession.self) private var session
    @State private var layout: TasksLayout = .board
    @State private var filter = TaskFilter()
    @State private var selection: HiveTask.ID?
    @State private var showsInspector = false
    @State private var showsNewTask = false

    var body: some View {
        let tasks = session.snapshot?.tasks ?? []
        Group {
            if tasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks Yet", systemImage: "checklist")
                } description: {
                    Text("Create a task for the agents, or let a connected agent add one.")
                } actions: {
                    Button("New Task") {
                        showsNewTask = true
                    }
                }
            } else {
                switch layout {
                case .board:
                    TaskBoardView(tasks: tasks, filter: filter, selection: $selection)
                case .list:
                    TaskListView(tasks: filter.apply(to: tasks), selection: $selection)
                }
            }
        }
        .searchable(text: $filter.searchText, prompt: "Search tasks")
        .toolbar {
            ToolbarItem {
                Picker("Layout", selection: $layout) {
                    Text("Board").tag(TasksLayout.board)
                    Text("List").tag(TasksLayout.list)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                TaskFilterMenu(filter: $filter)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Task", systemImage: "plus") {
                    showsNewTask = true
                }
                .help("Create a task for the agents")
            }
        }
        .inspector(isPresented: $showsInspector) {
            TaskInspector(taskID: selection)
                .inspectorColumnWidth(min: HiveMetrics.inspectorMinWidth, ideal: HiveMetrics.inspectorIdealWidth, max: HiveMetrics.inspectorMaxWidth)
        }
        .sheet(isPresented: $showsNewTask) {
            NewTaskSheet()
        }
        .onChange(of: selection) {
            showsInspector = selection != nil
        }
        .onChange(of: session.focusedTaskID, initial: true) {
            applyFocus()
        }
    }

    private func applyFocus() {
        guard let id = session.focusedTaskID else { return }
        filter.searchText = ""
        filter.minimumPriority = nil
        if session.snapshot?.task(withID: id)?.status == .cancelled {
            filter.showsCancelled = true
        }
        selection = id
        session.focusedTaskID = nil
    }
}

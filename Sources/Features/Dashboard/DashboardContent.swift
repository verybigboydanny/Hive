import SwiftUI

struct DashboardContent: View {
    let snapshot: ProjectSnapshot
    @Environment(ProjectSession.self) private var session
    @State private var showsNewTask = false

    private static let agentLimit = 6
    private static let taskLimit = 5
    private static let activityLimit = 8

    var body: some View {
        let attention = AttentionItem.items(from: snapshot)
        Form {
            Section {
                ProjectHeader(
                    project: snapshot.project,
                    overview: snapshot.overview,
                    isPreviewData: session.dataSource.isPreviewData
                )
            }

            Section {
                SummaryStrip(snapshot: snapshot)
                    .listRowBackground(Color.clear)
            }

            if !attention.isEmpty {
                Section("Needs Attention") {
                    ForEach(attention) { item in
                        AttentionRow(item: item) { open($0) }
                    }
                }
            }

            Section {
                if snapshot.agents.isEmpty {
                    ConnectAgentRow()
                } else {
                    ForEach(Array(snapshot.agents.prefix(Self.agentLimit).enumerated()), id: \.element.id) { index, agent in
                        Button {
                            session.showAgent(agent.id)
                        } label: {
                            AgentRow(agent: agent, currentTask: snapshot.task(withID: agent.currentTaskID))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.hivePress)
                        .hiveAppear(delay: 0.1 + Double(index) * 0.04)
                    }
                }
            } header: {
                DashboardSectionHeader(title: "Agents", destination: .agents)
            }

            Section {
                if snapshot.activeTasks.isEmpty {
                    Text("No active tasks")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(snapshot.activeTasks.prefix(Self.taskLimit).enumerated()), id: \.element.id) { index, task in
                        Button {
                            session.showTask(task.id)
                        } label: {
                            TaskRow(task: task, assignee: snapshot.agent(withID: task.assigneeID))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.hivePress)
                        .hiveAppear(delay: 0.15 + Double(index) * 0.04)
                    }
                }
            } header: {
                DashboardSectionHeader(title: "Active Tasks", destination: .tasks)
            }

            Section {
                if snapshot.activity.isEmpty {
                    Text("No activity yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.activity.prefix(Self.activityLimit)) { event in
                        ActivityRow(event: event)
                    }
                }
            } header: {
                DashboardSectionHeader(title: "Recent Activity", destination: .activity)
            }
        }
        .formStyle(.grouped)
        .hiveGroupedBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Task", systemImage: "plus") {
                    showNewTask()
                }
                    .help("Create a task for the agents")
            }
        }
        .sheet(isPresented: $showsNewTask) {
            NewTaskSheet()
        }
    }

    private func showNewTask() {
        showsNewTask = true
    }

    private func open(_ item: AttentionItem) {
        switch item.destination {
        case .task(let id): session.showTask(id)
        case .messages: session.selection = .messages
        }
    }
}

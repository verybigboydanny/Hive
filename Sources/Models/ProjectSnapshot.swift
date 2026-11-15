import Foundation

/// Everything the dashboard needs for one project at one moment.
struct ProjectSnapshot: Hashable, Sendable {
    var project: HiveProject
    var agents: [Agent]
    var tasks: [HiveTask]
    var handoffs: [Handoff]
    var activity: [ActivityEvent]
    /// Extra project-level numbers for the Dashboard. Defaulted so earlier call sites keep compiling.
    var overview: ProjectOverview = ProjectOverview()

    var connectedAgentCount: Int {
        agents.count(where: { $0.status != .offline })
    }

    var activeTasks: [HiveTask] {
        tasks.filter { $0.status == .inProgress || $0.status == .blocked || $0.status == .review }
    }

    var blockedTaskCount: Int {
        tasks.count(where: { $0.status == .blocked })
    }

    func agent(withID id: Agent.ID?) -> Agent? {
        guard let id else { return nil }
        return agents.first { $0.id == id }
    }

    func task(withID id: HiveTask.ID?) -> HiveTask? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }
}

import Foundation

/// TEMPORARY / DEV: fabricated data for previews, tests and `--hive-mock` runs.
/// It is stateful within a launch (creating a task or sending a message shows up afterwards) and forgets
/// everything, including which folders were initialized, when the app quits.
actor MockHiveDataSource: HiveDataSource {
    nonisolated let isPreviewData = true

    private var initializedPaths: Set<String> = []
    private var openProject: HiveProject?

    private var agents: [Agent]
    private var tasks: [HiveTask]
    private var handoffList: [Handoff]
    private var activityLog: [ActivityEvent]
    private var messageLog: [HiveMessage]
    private var trashItems: [TrashItem]
    private var nextCursor: Int
    private var nextSeq: Int
    private var nextTaskNumber = 100
    private var sampleIndex = 0

    init() {
        let seed = Self.seed()
        agents = seed.agents
        tasks = seed.tasks
        handoffList = seed.handoffs
        activityLog = seed.activity
        messageLog = seed.messages
        trashItems = seed.trash
        nextCursor = (seed.activity.map(\.cursor).max() ?? 0) + 1
        nextSeq = (seed.messages.map(\.seq).max() ?? 0) + 1
    }

    // MARK: Project lifecycle and dashboard

    func inspectProject(at url: URL) async throws -> ProjectInspection {
        try await Task.sleep(for: .milliseconds(250))
        guard initializedPaths.contains(url.path) else { return .notInitialized }
        let project = Self.project(for: url)
        openProject = project
        return .initialized(project)
    }

    func initializeProject(at url: URL) async throws -> HiveProject {
        try await Task.sleep(for: .milliseconds(700))
        initializedPaths.insert(url.path)
        let project = Self.project(for: url)
        openProject = project
        return project
    }

    func snapshot(for project: HiveProject) async throws -> ProjectSnapshot {
        try await Task.sleep(for: .milliseconds(200))
        openProject = project
        let newestFirst = activityLog.sorted { $0.cursor > $1.cursor }
        return ProjectSnapshot(
            project: project,
            agents: agents,
            tasks: tasks,
            handoffs: handoffList.filter { $0.status == .pending },
            activity: Array(newestFirst.prefix(50)),
            overview: ProjectOverview(
                expiredLeases: tasks.count(where: { $0.isLeaseExpired }),
                totalMessages: messageLog.count,
                memoryEntries: 3,
                activeDecisions: 1,
                git: GitSummary(branch: "main", head: "3f9c2d1", dirtyFiles: 2),
                createdAt: Self.ago(9 * 86_400)
            )
        )
    }

    nonisolated func events(for project: HiveProject) -> AsyncStream<ActivityEvent> {
        AsyncStream { continuation in
            let producer = Task { [self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled else { break }
                    continuation.yield(await self.appendSampleEvent())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    // MARK: Reads for the pages

    func handoffs(for project: HiveProject) async throws -> [Handoff] {
        handoffList.sorted { $0.createdAt > $1.createdAt }
    }

    func messages(for project: HiveProject, afterSeq: Int, limit: Int) async throws -> [HiveMessage] {
        Array(messageLog.filter { $0.seq > afterSeq }.sorted { $0.seq < $1.seq }.prefix(limit))
    }

    func activity(for project: HiveProject, afterID: Int?, limit: Int) async throws -> [ActivityEvent] {
        let ordered = activityLog.sorted { $0.cursor < $1.cursor }
        if let afterID {
            return Array(ordered.filter { $0.cursor > afterID }.prefix(limit))
        }
        return Array(ordered.suffix(limit))
    }

    func files(for project: HiveProject, path: String, includeHidden: Bool) async throws -> FileListing {
        try await Task.sleep(for: .milliseconds(80))
        let key = path == "." ? "" : path
        guard let children = Self.tree[key] else {
            throw HiveBackendError.api(code: "NOT_FOUND", message: "Folder not found: \(path)", hint: nil)
        }
        let entries = children
            .filter { includeHidden || !$0.name.hasPrefix(".") }
            .map { child -> FileEntry in
                let childPath = key.isEmpty ? child.name : "\(key)/\(child.name)"
                let size = child.isDirectory ? nil : Self.contents[childPath]?.utf8.count ?? 2_048
                return FileEntry(
                    name: child.name, path: childPath,
                    kind: child.isDirectory ? .directory : .file,
                    size: size, modified: Self.ago(Double(child.name.count) * 1_800)
                )
            }
        return FileListing(path: key.isEmpty ? "." : key, entries: entries, truncated: false)
    }

    func fileContent(for project: HiveProject, path: String, startLine: Int, maxLines: Int) async throws -> FileContent {
        try await Task.sleep(for: .milliseconds(80))
        if path.hasSuffix(".bin") {
            throw HiveBackendError.api(code: "NOT_TEXT", message: "File is not UTF-8 text.", hint: nil)
        }
        guard let text = Self.contents[path] else {
            throw HiveBackendError.api(code: "NOT_FOUND", message: "File not found: \(path)", hint: nil)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let first = max(startLine, 1)
        let slice = Array(lines.dropFirst(first - 1).prefix(maxLines))
        let end = first - 1 + slice.count
        let more = end < lines.count
        return FileContent(
            path: path, content: slice.joined(separator: "\n"), sha256: String(repeating: "ab12", count: 16),
            size: text.utf8.count, totalLines: lines.count, startLine: first, endLine: end,
            truncated: more, nextStartLine: more ? end + 1 : nil
        )
    }

    func trash(for project: HiveProject) async throws -> [TrashItem] {
        trashItems
    }

    // MARK: App-level reads

    func backendHealth() async throws -> BackendHealth {
        BackendHealth(
            apiStatus: "ok", apiUptimeSeconds: 3_725, backendVersion: "0.1.0", contractVersion: "0.1.0",
            workspaceOpen: openProject != nil, workspaceStatus: openProject == nil ? nil : "ok",
            databaseOK: openProject == nil ? nil : true, schemaVersion: openProject == nil ? nil : 2,
            expectedSchemaVersion: openProject == nil ? nil : 2, workspaceFoldersOK: openProject == nil ? nil : true,
            stats: openProject == nil ? [:] : [
                "agents": agents.count, "open_sessions": 3, "pending_handoffs": handoffList.count(where: { $0.status == .pending }),
                "open_tasks": tasks.count(where: { $0.status != .done && $0.status != .cancelled }), "expired_leases": 0
            ],
            processID: 4_242
        )
    }

    func currentWorkspace() async throws -> WorkspaceInfo? {
        guard let openProject else { return nil }
        return WorkspaceInfo(
            name: openProject.name, root: openProject.rootURL.path, createdAt: Self.ago(9 * 86_400),
            schemaVersion: 2, backendVersion: "0.1.0", contractVersion: "0.1.0", projectID: "prj_0000000000000000"
        )
    }

    func currentContext() async throws -> ProjectContext? {
        guard openProject != nil else { return nil }
        return Self.context
    }

    // MARK: Writes

    func createTask(for project: HiveProject, draft: NewTaskDraft) async throws -> HiveTask {
        try await Task.sleep(for: .milliseconds(150))
        nextTaskNumber += 1
        let blockers = draft.dependsOn.compactMap { id in
            tasks.first { $0.id == id && $0.status != .done }.map { HiveTask.Blocker(id: $0.id, status: "open") }
        }
        let task = HiveTask(
            id: "task-\(nextTaskNumber)", title: draft.title, summary: draft.details, status: .backlog,
            assigneeID: nil, progress: nil, dependencyIDs: draft.dependsOn, updatedAt: .now,
            details: draft.details, priority: draft.priority, labels: draft.labels,
            blockedBy: blockers, isClaimable: blockers.isEmpty, createdBy: "user", createdAt: .now
        )
        tasks.append(task)
        record(.taskUpdated, action: "task.create", summary: "created task '\(draft.title)'", target: task.id)
        return task
    }

    func cancelTask(for project: HiveProject, taskID: String, reason: String) async throws -> HiveTask {
        try await Task.sleep(for: .milliseconds(120))
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw HiveBackendError.api(code: "NOT_FOUND", message: "Task not found: \(taskID)", hint: nil)
        }
        tasks[index].status = .cancelled
        tasks[index].cancelReason = reason
        tasks[index].updatedAt = .now
        record(.taskUpdated, action: "task.cancel", summary: "cancelled task '\(tasks[index].title)': \(reason)", target: taskID)
        return tasks[index]
    }

    func releaseTask(for project: HiveProject, taskID: String) async throws -> HiveTask {
        try await Task.sleep(for: .milliseconds(120))
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw HiveBackendError.api(code: "NOT_FOUND", message: "Task not found: \(taskID)", hint: nil)
        }
        tasks[index].status = .backlog
        tasks[index].assigneeID = nil
        tasks[index].ownerName = nil
        tasks[index].leaseExpiresAt = nil
        tasks[index].isClaimable = tasks[index].blockedBy.isEmpty
        tasks[index].updatedAt = .now
        record(.taskUpdated, action: "task.update", summary: "released task '\(tasks[index].title)'", target: taskID)
        return tasks[index]
    }

    func sendMessage(for project: HiveProject, draft: NewMessageDraft) async throws -> HiveMessage {
        try await Task.sleep(for: .milliseconds(120))
        let recipient = agents.first { $0.id == draft.to }
        let message = HiveMessage(
            id: "msg-\(nextSeq)", seq: nextSeq, threadID: "thr-\(nextSeq)", kind: draft.kind,
            fromID: "user", fromName: "You", fromKind: "human",
            toID: draft.to == "all" ? nil : draft.to, toName: recipient?.name,
            subject: draft.subject, body: draft.body, taskID: draft.taskID, createdAt: .now
        )
        nextSeq += 1
        messageLog.append(message)
        record(.message, action: "message.send", summary: "sent a message to \(recipient?.name ?? "everyone")", target: message.id)
        return message
    }

    func restoreTrashItem(for project: HiveProject, trashID: String) async throws {
        try await Task.sleep(for: .milliseconds(120))
        guard let item = trashItems.first(where: { $0.trashID == trashID }) else {
            throw HiveBackendError.api(code: "NOT_FOUND", message: "Trash item not found.", hint: nil)
        }
        trashItems.removeAll { $0.trashID == trashID }
        record(.fileModified, action: "file.restore", summary: "restored \(item.originalPath)", target: item.originalPath)
    }

    func removeAgent(for project: HiveProject, agentID: String) async throws {
        try await Task.sleep(for: .milliseconds(150))
        guard agents.firstIndex(where: { $0.id == agentID }) != nil else {
            throw HiveBackendError.api(code: "NOT_FOUND", message: "Agent not found: \(agentID)", hint: nil)
        }
        agents.removeAll { $0.id == agentID }
        record(.agentDisconnected, action: "agent.remove", summary: "removed agent \(agentID)", target: agentID)
    }

    func onboarding(for project: HiveProject, setup: AgentSetupRequest) async throws -> AgentOnboarding {
        try await Task.sleep(for: .milliseconds(150))
        let id = project.projectID ?? "prj_0000000000000000"
        return AgentOnboarding(
            prompt: "PREVIEW DATA. Register `\(setup.name)` in project \(id) with `agent_register`.",
            projectID: id, projectName: project.name, warnings: []
        )
    }

    // MARK: Live-event simulation

    private func appendSampleEvent() -> ActivityEvent {
        defer { sampleIndex += 1 }
        switch sampleIndex % 4 {
        case 0:
            return record(.fileModified, action: "file.write", summary: "wrote Sources/Watcher/EventStream.swift", actor: "Ken", target: "Sources/Watcher/EventStream.swift")
        case 1:
            let message = HiveMessage(
                id: "msg-\(nextSeq)", seq: nextSeq, threadID: "thr-ada", kind: .notice, fromID: "agent-ada", fromName: "Ada",
                fromKind: "agent", toID: nil, toName: nil, subject: "Ready for review",
                body: "Token refresh is ready for review.", taskID: "task-auth", createdAt: .now
            )
            nextSeq += 1
            messageLog.append(message)
            return record(.message, action: "message.send", summary: "sent a message to everyone", actor: "Ada", target: message.id)
        case 2:
            return record(.taskUpdated, action: "task.update", summary: "updated progress on 'Implement token refresh'", actor: "Ada", target: "task-auth")
        default:
            return record(.checkpoint, action: "checkpoint.save", summary: "saved a checkpoint", actor: "Ken", target: "ckp_mock")
        }
    }

    @discardableResult
    private func record(_ kind: ActivityEvent.Kind, action: String, summary: String, actor: String = "You", target: String? = nil) -> ActivityEvent {
        let event = ActivityEvent(
            id: String(nextCursor), kind: kind, agentName: actor, summary: summary, timestamp: .now,
            action: action, targetType: String(action.prefix(while: { $0 != "." })), targetID: target,
            actorID: actor == "You" ? "user" : nil, actorKind: actor == "You" ? "human" : "agent", detailsJSON: nil
        )
        nextCursor += 1
        activityLog.append(event)
        return event
    }

    // MARK: Sample data

    private static func project(for url: URL) -> HiveProject {
        HiveProject(name: url.lastPathComponent, rootURL: url, status: .ready, projectID: "prj_0000000000000000")
    }

    private static func ago(_ seconds: TimeInterval) -> Date {
        Date.now.addingTimeInterval(-seconds)
    }

    private struct Seed {
        var agents: [Agent]
        var tasks: [HiveTask]
        var handoffs: [Handoff]
        var activity: [ActivityEvent]
        var messages: [HiveMessage]
        var trash: [TrashItem]
    }

    private static func seed() -> Seed {
        let agents = [
            Agent(id: "agent-ada", name: "Ada", clientName: "claude", status: .working, currentTaskID: "task-auth", lastActivity: ago(20),
                  role: "Backend: authentication", model: "claude-sonnet", capabilities: ["swift", "python", "testing"],
                  statusMessage: "Wiring token refresh into the session store", reportedStatus: "active", presence: "online",
                  registeredAt: ago(2 * 86_400), openSessions: 1, activeTaskIDs: ["task-auth"]),
            Agent(id: "agent-linus", name: "Linus", clientName: "gpt", status: .online, currentTaskID: "task-tests", lastActivity: ago(4 * 60),
                  role: "Test engineer", model: "gpt-5", capabilities: ["testing"], statusMessage: "Waiting on token refresh",
                  reportedStatus: "blocked", presence: "online", registeredAt: ago(2 * 86_400), openSessions: 1, activeTaskIDs: ["task-tests"]),
            Agent(id: "agent-grace", name: "Grace", clientName: "gemini", status: .idle, currentTaskID: nil, lastActivity: ago(12 * 60),
                  role: "Schema design", model: "gemini-pro", capabilities: ["design", "docs"], reportedStatus: "idle", presence: "away",
                  registeredAt: ago(3 * 86_400), openSessions: 1, activeTaskIDs: []),
            Agent(id: "agent-ken", name: "Ken", clientName: "cursor", status: .working, currentTaskID: "task-watcher", lastActivity: ago(45),
                  role: "File watching", capabilities: ["swift"], statusMessage: "Replacing polling with FSEvents",
                  reportedStatus: "active", presence: "online", registeredAt: ago(86_400), openSessions: 1, activeTaskIDs: ["task-watcher"]),
            Agent(id: "agent-mira", name: "Mira", clientName: "windsurf", status: .offline, currentTaskID: nil, lastActivity: ago(3 * 3_600),
                  reportedStatus: "offline", presence: "offline", registeredAt: ago(5 * 86_400), openSessions: 0, activeTaskIDs: [])
        ]

        let tasks = [
            HiveTask(id: "task-auth", title: "Implement token refresh", summary: "Refresh expiring sessions without interrupting the user.",
                     status: .inProgress, assigneeID: "agent-ada", progress: nil, dependencyIDs: [], updatedAt: ago(20),
                     details: "Refresh expiring sessions without interrupting the user. Acceptance: a refresh happens 60 s before expiry.",
                     priority: .high, labels: ["auth"], ownerName: "Ada", leaseExpiresAt: Date.now.addingTimeInterval(22 * 60),
                     version: 4, progressNote: "Store done; wiring the timer.", createdBy: "user", createdAt: ago(2 * 86_400)),
            HiveTask(id: "task-tests", title: "Integration tests for sync", summary: "Cover the sync happy path and conflict resolution.",
                     status: .blocked, assigneeID: "agent-linus", progress: nil, dependencyIDs: ["task-auth"], updatedAt: ago(4 * 60),
                     details: "Cover the sync happy path and conflict resolution.", priority: .normal, labels: ["tests"], ownerName: "Linus",
                     leaseExpiresAt: Date.now.addingTimeInterval(9 * 60),
                     blockedBy: [HiveTask.Blocker(id: "task-auth", status: "in_progress")], version: 3,
                     progressNote: "Waiting for token refresh.", createdBy: "agent-ada", createdAt: ago(2 * 86_400)),
            HiveTask(id: "task-schema", title: "Design settings schema", summary: "Define the shape of project-level settings.",
                     status: .review, assigneeID: "agent-grace", progress: nil, dependencyIDs: [], updatedAt: ago(12 * 60),
                     details: "Define the shape of project-level settings.", priority: .normal, labels: ["design"], ownerName: "Grace",
                     leaseExpiresAt: Date.now.addingTimeInterval(-2 * 60), isLeaseExpired: true, isClaimable: true, version: 6,
                     progressNote: "Ready for review.", createdBy: "user", createdAt: ago(3 * 86_400)),
            HiveTask(id: "task-watcher", title: "Move file watcher to FSEvents", summary: "Replace polling with FSEvents.",
                     status: .inProgress, assigneeID: "agent-ken", progress: nil, dependencyIDs: [], updatedAt: ago(45),
                     details: "Replace polling with FSEvents.", priority: .urgent, labels: ["perf"], ownerName: "Ken",
                     leaseExpiresAt: Date.now.addingTimeInterval(28 * 60), version: 2, createdBy: "user", createdAt: ago(86_400)),
            HiveTask(id: "task-docs", title: "Document MCP tool usage", summary: "Write usage notes for connected agents.",
                     status: .backlog, assigneeID: nil, progress: nil, dependencyIDs: [], updatedAt: ago(2 * 3_600),
                     details: "Write usage notes for connected agents.", priority: .low, labels: ["docs"], isClaimable: true,
                     createdBy: "user", createdAt: ago(86_400)),
            HiveTask(id: "task-ci", title: "Set up CI checks", summary: "Build and test succeeded on every change.",
                     status: .done, assigneeID: "agent-grace", progress: nil, dependencyIDs: [], updatedAt: ago(5 * 3_600),
                     details: "Run build and tests on every change.", priority: .normal, ownerName: "Grace", version: 5,
                     resultSummary: "Build and test succeeded on every change.", createdBy: "user", createdAt: ago(4 * 86_400),
                     completedAt: ago(5 * 3_600))
        ]

        let handoffs = [
            Handoff(id: "hnd-1", taskTitle: "Design settings schema", fromAgentName: "Grace", toAgentName: nil, createdAt: ago(12 * 60),
                    status: .pending, taskID: "task-schema", fromID: "agent-grace", summary: "Settings schema drafted, needs an implementer",
                    completedWork: "Drafted schema and validation rules.", remainingWork: "Wire it into the settings screen.",
                    filesModified: ["docs/architecture.md"], nextAction: "Read docs/architecture.md, then claim the task.",
                    context: "Keep the schema backward compatible with config.json."),
            Handoff(id: "hnd-0", taskTitle: "Set up CI checks", fromAgentName: "Mira", toAgentName: "Grace", createdAt: ago(6 * 3_600),
                    status: .accepted, taskID: "task-ci", fromID: "agent-mira", toID: "agent-grace", summary: "CI half done",
                    completedWork: "Build job.", remainingWork: "Test job.", filesModified: [], nextAction: "Add the test job.",
                    acceptedByName: "Grace", acceptedAt: ago(5 * 3_600 + 1_800))
        ]

        let activity: [(ActivityEvent.Kind, String, String, String?, String, TimeInterval)] = [
            (.agentConnected, "agent.register", "registered as Mira", "Mira", "agent-mira", 5 * 86_400),
            (.taskUpdated, "task.create", "created task 'Implement token refresh'", "You", "task-auth", 2 * 86_400),
            (.agentDisconnected, "agent.disconnect", "disconnected", "Mira", "agent-mira", 3 * 3_600),
            (.agentConnected, "agent.reconnect", "reconnected", "Ken", "agent-ken", 50 * 60),
            (.checkpoint, "checkpoint.save", "saved a checkpoint before pausing on a dependency", "Linus", "ckp_1", 14 * 60),
            (.handoff, "handoff.create", "handed 'Design settings schema' to anyone", "Grace", "hnd-1", 12 * 60),
            (.taskUpdated, "task.update", "moved 'Move file watcher to FSEvents' to in progress", "Ken", "task-watcher", 45),
            (.fileModified, "file.write", "wrote Sources/Auth/TokenStore.swift", "Ada", "Sources/Auth/TokenStore.swift", 20)
        ]
        let events = activity.enumerated().map { index, row in
            ActivityEvent(
                id: String(index + 1), kind: row.0, agentName: row.3, summary: row.2, timestamp: ago(row.5),
                action: row.1, targetType: String(row.1.prefix(while: { $0 != "." })), targetID: row.4,
                actorID: row.3 == "You" ? "user" : nil, actorKind: row.3 == "You" ? "human" : "agent",
                detailsJSON: row.1 == "file.write" ? "{\n  \"size\": 2210,\n  \"previous_sha256\": \"9f2c…\"\n}" : nil
            )
        }

        func message(_ seq: Int, _ kind: HiveMessage.Kind, _ from: (String, String, String), _ to: (String, String)?,
                     _ subject: String?, _ body: String, _ task: String?, _ ago: TimeInterval) -> HiveMessage {
            HiveMessage(id: "msg-\(seq)", seq: seq, threadID: "thr-\(seq)", kind: kind, fromID: from.0, fromName: from.1, fromKind: from.2,
                        toID: to?.0, toName: to?.1, subject: subject, body: body, taskID: task, createdAt: Self.ago(ago))
        }
        let messages = [
            message(1, .notice, ("agent-ada", "Ada", "agent"), nil, "Starting auth", "Starting on token refresh; touching Sources/Auth only.", "task-auth", 2 * 3_600),
            message(2, .question, ("agent-linus", "Linus", "agent"), ("agent-ada", "Ada"), "Refresh endpoint", "Is the refresh endpoint stable enough to test against?", "task-auth", 90 * 60),
            message(3, .answer, ("agent-ada", "Ada", "agent"), ("agent-linus", "Linus"), nil, "Not yet. I will message you when the store is merged.", "task-auth", 80 * 60),
            message(4, .notice, ("user", "You", "human"), nil, "Commit size", "Please keep changes small and checkpoint often.", nil, 70 * 60),
            message(5, .message, ("agent-grace", "Grace", "agent"), ("agent-ken", "Ken"), nil, "The settings schema is in docs/architecture.md if you need it.", "task-schema", 20 * 60)
        ]

        let trash = [
            TrashItem(trashID: "trash_a1b2c3d4e5", originalPath: "Sources/Legacy/OldWatcher.swift", kind: "file", entries: 1,
                      deletedAt: ago(3 * 3_600), deletedBy: "Ken", reason: "Replaced by the FSEvents implementation")
        ]
        return Seed(agents: agents, tasks: tasks, handoffs: handoffs, activity: events, messages: messages, trash: trash)
    }

    private struct Node {
        let name: String
        let isDirectory: Bool
    }

    private static let tree: [String: [Node]] = [
        "": [Node(name: "Sources", isDirectory: true), Node(name: "Tests", isDirectory: true), Node(name: "docs", isDirectory: true),
             Node(name: "Package.swift", isDirectory: false), Node(name: "README.md", isDirectory: false), Node(name: "logo.bin", isDirectory: false)],
        "Sources": [Node(name: "Auth", isDirectory: true), Node(name: "Watcher", isDirectory: true), Node(name: "main.swift", isDirectory: false)],
        "Sources/Auth": [Node(name: "TokenStore.swift", isDirectory: false), Node(name: "Session.swift", isDirectory: false)],
        "Sources/Watcher": [Node(name: "EventStream.swift", isDirectory: false)],
        "Tests": [Node(name: "TokenStoreTests.swift", isDirectory: false)],
        "docs": [Node(name: "architecture.md", isDirectory: false)]
    ]

    private static let contents: [String: String] = [
        "README.md": "# Example project\n\nA small project coordinated by Hive.\n\n## Layout\n- `Sources/` application code\n- `Tests/` tests\n- `docs/` notes\n",
        "Package.swift": "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"Example\",\n    targets: [\n        .executableTarget(name: \"Example\", path: \"Sources\"),\n        .testTarget(name: \"ExampleTests\", dependencies: [\"Example\"], path: \"Tests\")\n    ]\n)\n",
        "Sources/main.swift": "import Foundation\n\nprint(\"Hello from Example\")\n",
        "Sources/Auth/TokenStore.swift": "import Foundation\n\nactor TokenStore {\n    private var token: String?\n    private var expiry: Date?\n\n    func save(_ token: String, expiresAt: Date) {\n        self.token = token\n        self.expiry = expiresAt\n    }\n\n    func validToken(now: Date = .now) -> String? {\n        guard let token, let expiry, expiry > now else { return nil }\n        return token\n    }\n}\n",
        "Sources/Auth/Session.swift": "struct Session {\n    let userID: String\n}\n",
        "Sources/Watcher/EventStream.swift": "import Foundation\n\n// FSEvents-based watcher (in progress).\nfinal class EventStream {}\n",
        "Tests/TokenStoreTests.swift": "import Testing\n\n@Test func savesAndReadsToken() async {}\n",
        "docs/architecture.md": "# Architecture\n\nThe settings schema keeps `config.json` backward compatible.\n"
    ]

    private static let context = ProjectContext(
        protocolRules: "# Hive working rules (built in)\n1. Register once with `agent_register`; keep the returned `agent_id` and `resume_token` to reconnect.\n2. Start every session with `agent_get_context`.\n3. Claim a task (`task_claim`) before working on it.\n4. Read a file before changing it and pass its `sha256` as `expected_sha256` to `write_file`.\n5. Save a checkpoint (`save_checkpoint`) at meaningful milestones.\n6. Hand work over with `handoff_create`.\n",
        projectRules: [
            MemoryEntry(id: "mem-1", key: "rules/commits", category: "rules", value: "Keep commits small. One logical change per commit.",
                        tags: ["git"], version: 2, updatedByName: "Ada", updatedAt: ago(86_400))
        ],
        decisions: [
            DecisionRecord(id: "dec-1", title: "Use actors for shared state", decision: "Shared mutable state lives in actors.",
                           rationale: "Avoids data races under Swift 6.", tags: ["concurrency"], status: "active",
                           decidedByName: "Ada", createdAt: ago(2 * 86_400))
        ],
        memory: [
            MemoryEntry(id: "mem-2", key: "architecture/db", category: "architecture", value: "SQLite is owned by the backend; the UI never opens it.",
                        tags: ["backend"], version: 1, updatedByName: "Grace", updatedAt: ago(3 * 86_400)),
            MemoryEntry(id: "mem-1", key: "rules/commits", category: "rules", value: "Keep commits small. One logical change per commit.",
                        tags: ["git"], version: 2, updatedByName: "Ada", updatedAt: ago(86_400))
        ]
    )
}

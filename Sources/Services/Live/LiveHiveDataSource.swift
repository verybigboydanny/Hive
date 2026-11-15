import Foundation

/// Owns the local Hive API process and maps its documented HTTP contract to UI models.
actor LiveHiveDataSource: HiveDataSource {
    nonisolated let isPreviewData = false

    private struct ReadyMessage: Decodable {
        let event: String
        let host: String
        let port: Int
        let token: String
    }

    private var process: Process?
    private var baseURL: URL?
    private var token: String?
    private var lastEventCursor = 0
    private var workspacePath: String?

    func stop() async {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            let deadline = ContinuousClock.now + .seconds(10)
            while process.isRunning, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        self.process = nil
        baseURL = nil
        token = nil
        workspacePath = nil
    }

    func inspectProject(at url: URL) async throws -> ProjectInspection {
        do {
            let info = try await request("workspace/open", method: "POST", body: ["path": url.path])
            let project = makeProject(info, fallbackURL: url)
            workspacePath = project.rootURL.path
            return .initialized(project)
        } catch let error as HiveBackendError {
            if case .api(code: "NOT_INITIALIZED", message: _, hint: _) = error {
                return .notInitialized
            }
            throw error
        }
    }

    func initializeProject(at url: URL) async throws -> HiveProject {
        let info = try await request("workspace/init", method: "POST", body: [
            "path": url.path,
            "name": url.lastPathComponent
        ])
        let project = makeProject(info, fallbackURL: url)
        workspacePath = project.rootURL.path
        return project
    }

    func snapshot(for project: HiveProject) async throws -> ProjectSnapshot {
        try await openWorkspaceIfNeeded(project)

        let status = try await request("project/status")
        let taskResponse = try await request("tasks?include_closed=true&limit=500")
        let handoffResponse = try await request("handoffs?status=pending&limit=200")
        let activityResponse = try await request("activity?limit=50")

        let tasks = array(taskResponse["tasks"]).map(mapTask)
        let agents = array(status["agents"])
            .filter { string($0["kind"]) != "human" }
            .map { mapAgent($0, tasks: tasks) }
        let handoffs = array(handoffResponse["handoffs"]).map { mapHandoff($0, tasks: tasks) }
        let activity = array(activityResponse["entries"]).map(mapActivity).sorted { cursor($0.id) > cursor($1.id) }
        lastEventCursor = activity.map { cursor($0.id) }.max() ?? 0

        return ProjectSnapshot(
            project: project,
            agents: agents,
            tasks: tasks,
            handoffs: handoffs,
            activity: activity,
            overview: makeOverview(status)
        )
    }

    nonisolated func events(for project: HiveProject) -> AsyncStream<ActivityEvent> {
        AsyncStream { continuation in
            let poller = Task { [weak self] in
                await self?.pollActivity(for: project, continuation: continuation)
            }
            continuation.onTermination = { _ in poller.cancel() }
        }
    }

    // MARK: - Process and HTTP transport

    private func ensureAPIIsRunning() throws {
        if let process, process.isRunning, baseURL != nil, token != nil { return }
        if process != nil {
            workspacePath = nil
            baseURL = nil
            token = nil
        }

        let pythonSource = Bundle.main.resourceURL?.appending(path: "hive-backend/src")
        guard let pythonSource,
              FileManager.default.fileExists(atPath: pythonSource.appending(path: "hive").path) else {
            throw HiveBackendError.serviceUnavailable("Hive's bundled backend files are missing from the app.")
        }

        let output = Pipe()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.arguments = ["python3", "-u", "-m", "hive", "api"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["PYTHONPATH"] = pythonSource.path
        // The backend runs from inside the signed app bundle, whose resources should stay read-only.
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice

        do {
            try child.run()
            process = child
            let line = try readReadyLine(from: output.fileHandleForReading)
            let ready = try JSONDecoder().decode(ReadyMessage.self, from: Data(line.utf8))
            guard ready.event == "ready", ["127.0.0.1", "localhost", "::1"].contains(ready.host),
                  let url = URL(string: "http://127.0.0.1:\(ready.port)/v1/") else {
                child.terminate()
                process = nil
                throw HiveBackendError.invalidResponse
            }
            baseURL = url
            token = ready.token
        } catch let error as HiveBackendError {
            if child.isRunning { child.terminate() }
            process = nil
            throw error
        } catch {
            if child.isRunning { child.terminate() }
            process = nil
            throw HiveBackendError.serviceUnavailable(
                "Could not start Hive's local API. Install Python 3.11 or later, then reopen Hive. (\(error.localizedDescription))"
            )
        }
    }

    private func readReadyLine(from handle: FileHandle) throws -> String {
        var bytes = Data()
        while bytes.count < 16_384 {
            let chunk = handle.availableData
            guard !chunk.isEmpty else { throw HiveBackendError.invalidResponse }
            if let newline = chunk.firstIndex(of: 10) {
                bytes.append(chunk[..<newline])
                guard let line = String(data: bytes, encoding: .utf8) else {
                    throw HiveBackendError.invalidResponse
                }
                return line
            }
            bytes.append(chunk)
        }
        throw HiveBackendError.invalidResponse
    }

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        try ensureAPIIsRunning()
        guard let baseURL, let token,
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HiveBackendError.invalidResponse
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HiveBackendError.serviceUnavailable("Could not reach Hive's local API. \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse,
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HiveBackendError.invalidResponse
        }
        if http.statusCode >= 400 || (envelope["ok"] as? Bool) == false {
            let error = envelope["error"] as? [String: Any] ?? [:]
            throw HiveBackendError.api(
                code: string(error["code"]) ?? "HTTP_\(http.statusCode)",
                message: string(error["message"]) ?? "Hive's API request failed.",
                hint: string(error["hint"])
            )
        }
        guard let payload = envelope["data"] as? [String: Any] else {
            throw HiveBackendError.invalidResponse
        }
        return payload
    }

    func openWorkspaceIfNeeded(_ project: HiveProject) async throws {
        guard workspacePath != project.rootURL.path else { return }
        let info = try await request("workspace/open", method: "POST", body: ["path": project.rootURL.path])
        let opened = makeProject(info, fallbackURL: project.rootURL)
        workspacePath = opened.rootURL.path
    }

    // MARK: - Contract mapping

    private func makeProject(_ value: [String: Any], fallbackURL: URL) -> HiveProject {
        let root = string(value["root"]).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? fallbackURL
        return HiveProject(
            name: string(value["name"]) ?? root.lastPathComponent, rootURL: root, status: .ready,
            projectID: string(value["id"])
        )
    }

    func mapAgent(_ value: [String: Any], tasks: [HiveTask]) -> Agent {
        let activeTaskIDs = strings(value["active_task_ids"])
        let presence = string(value["presence"]) ?? "offline"
        let status: Agent.Status
        if presence == "offline" {
            status = .offline
        } else if !activeTaskIDs.isEmpty {
            status = .working
        } else if presence == "away" {
            status = .idle
        } else {
            status = .online
        }
        let agentID = string(value["id"])
        let taskID = activeTaskIDs.first ?? tasks.first(where: { $0.assigneeID == agentID && $0.status == .inProgress })?.id
        return Agent(
            id: string(value["id"]) ?? UUID().uuidString,
            name: string(value["name"]) ?? "Hive agent",
            clientName: string(value["client"]) ?? "Unknown client",
            status: status,
            currentTaskID: taskID,
            lastActivity: date(value["last_seen_at"]),
            role: string(value["role"]),
            model: string(value["model"]),
            capabilities: strings(value["capabilities"]),
            statusMessage: string(value["status_message"]),
            reportedStatus: string(value["status"]),
            presence: string(value["presence"]),
            registeredAt: optionalDate(value["registered_at"]),
            openSessions: cursor(value["open_sessions"]),
            activeTaskIDs: activeTaskIDs
        )
    }

    func mapTask(_ value: [String: Any]) -> HiveTask {
        let backendStatus = string(value["status"]) ?? "open"
        let status: HiveTask.Status = switch backendStatus {
        case "claimed", "in_progress": .inProgress
        case "blocked": .blocked
        case "review": .review
        case "done": .done
        case "cancelled": .cancelled
        default: .backlog
        }
        let description = string(value["description"]) ?? ""
        let resultSummary = string(value["result_summary"])
        let progressNote = string(value["progress_note"])
        let summary = resultSummary ?? progressNote ?? description
        return HiveTask(
            id: string(value["id"]) ?? UUID().uuidString,
            title: string(value["title"]) ?? "Untitled task",
            summary: summary,
            status: status,
            assigneeID: string(value["owner_id"]),
            progress: nil,
            dependencyIDs: strings(value["depends_on"]),
            updatedAt: date(value["updated_at"]),
            details: description,
            priority: HiveTask.Priority(rawValue: string(value["priority"]) ?? "") ?? .normal,
            labels: strings(value["labels"]),
            ownerName: string(value["owner_name"]),
            leaseExpiresAt: optionalDate(value["claim_expires_at"]),
            isLeaseExpired: bool(value["lease_expired"]),
            blockedBy: array(value["blocked_by"]).map {
                HiveTask.Blocker(id: string($0["id"]) ?? "", status: string($0["status"]) ?? "")
            },
            isClaimable: bool(value["claimable"]),
            version: max(cursor(value["version"]), 1),
            progressNote: string(value["progress_note"]),
            resultSummary: string(value["result_summary"]),
            cancelReason: string(value["cancel_reason"]),
            createdBy: string(value["created_by"]),
            parentID: string(value["parent_id"]),
            createdAt: optionalDate(value["created_at"]),
            completedAt: optionalDate(value["completed_at"])
        )
    }

    func mapHandoff(_ value: [String: Any], tasks: [HiveTask]) -> Handoff {
        let taskID = string(value["task_id"])
        let handoffSummary = string(value["summary"])
        let taskTitle = tasks.first(where: { $0.id == taskID })?.title ?? handoffSummary ?? "Handoff"
        return Handoff(
            id: string(value["id"]) ?? UUID().uuidString,
            taskTitle: taskTitle,
            fromAgentName: string(value["from_name"]) ?? "Unknown agent",
            toAgentName: string(value["to_name"]),
            createdAt: date(value["created_at"]),
            status: Handoff.Status(rawValue: string(value["status"]) ?? "") ?? .pending,
            taskID: taskID,
            fromID: string(value["from_id"]),
            toID: string(value["to_id"]),
            summary: string(value["summary"]) ?? "",
            completedWork: string(value["completed_work"]),
            remainingWork: string(value["remaining_work"]),
            filesModified: strings(value["files_modified"]),
            nextAction: string(value["next_action"]),
            context: string(value["context"]),
            acceptedByName: string(value["accepted_by_name"]),
            acceptedAt: optionalDate(value["accepted_at"])
        )
    }

    func mapActivity(_ value: [String: Any]) -> ActivityEvent {
        let action = string(value["action"]) ?? ""
        let kind: ActivityEvent.Kind
        switch action {
        case let a where a.hasPrefix("file."): kind = .fileModified
        case let a where a.hasPrefix("task."): kind = .taskUpdated
        case "agent.register", "agent.reconnect": kind = .agentConnected
        case "agent.disconnect": kind = .agentDisconnected
        case let a where a.hasPrefix("checkpoint."): kind = .checkpoint
        case let a where a.hasPrefix("handoff."): kind = .handoff
        case "message.send": kind = .message
        default: kind = .other
        }
        let actor = value["actor"] as? [String: Any]
        let actorName = string(actor?["kind"]) == "human" ? "You" : string(actor?["name"])
        let rawAgentID = string(value["agent_id"])
        return ActivityEvent(
            id: String(cursor(value["id"])),
            kind: kind,
            agentName: actorName ?? rawAgentID.map { $0 == "user" ? "You" : $0 },
            summary: string(value["summary"]) ?? action,
            timestamp: date(value["ts"]),
            action: action,
            targetType: string(value["target_type"]),
            targetID: string(value["target_id"]),
            actorID: string(actor?["id"]) ?? rawAgentID,
            actorKind: string(actor?["kind"]),
            detailsJSON: prettyJSON(value["details"])
        )
    }

    private func pollActivity(for project: HiveProject, continuation: AsyncStream<ActivityEvent>.Continuation) async {
        var cursor = lastEventCursor
        while !Task.isCancelled {
            do {
                try await openWorkspaceIfNeeded(project)
                let response = try await request("activity?after_id=\(cursor)&limit=100")
                let entries = array(response["entries"]).map(mapActivity)
                for event in entries where !Task.isCancelled {
                    let next = Self.cursor(event.id)
                    guard next > cursor else { continue }
                    continuation.yield(event)
                    cursor = next
                    lastEventCursor = next
                }
            } catch is CancellationError {
                break
            } catch {
                // The next poll retries; snapshot reload surfaces request failures to the user.
            }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                break
            }
        }
        continuation.finish()
    }

    // MARK: - Small JSON/date helpers

    func array(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    func strings(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return value as? String
    }

    func date(_ value: Any?) -> Date {
        guard let value = string(value) else { return .distantPast }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: value) { return parsed }
        let ordinary = ISO8601DateFormatter()
        ordinary.formatOptions = [.withInternetDateTime]
        return ordinary.date(from: value) ?? .distantPast
    }

    func optionalDate(_ value: Any?) -> Date? {
        string(value) == nil ? nil : date(value)
    }

    func bool(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    /// Pretty-prints a JSON object for display; nil when it is empty or not an object.
    func prettyJSON(_ value: Any?) -> String? {
        guard let object = value as? [String: Any], !object.isEmpty, JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func makeOverview(_ status: [String: Any]) -> ProjectOverview {
        let tasks = status["tasks"] as? [String: Any]
        let messages = status["messages"] as? [String: Any]
        let memory = status["memory"] as? [String: Any]
        let project = status["project"] as? [String: Any]
        var git: GitSummary?
        if let raw = status["git"] as? [String: Any], bool(raw["is_repo"]) {
            git = GitSummary(
                branch: string(raw["branch"]),
                head: string(raw["head"]),
                dirtyFiles: raw["dirty_files"] is NSNull ? nil : (raw["dirty_files"] as? NSNumber)?.intValue
            )
        }
        return ProjectOverview(
            expiredLeases: cursor(tasks?["expired_leases"]),
            totalMessages: cursor(messages?["total"]),
            memoryEntries: cursor(memory?["entries"]),
            activeDecisions: cursor(memory?["active_decisions"]),
            git: git,
            createdAt: optionalDate(project?["created_at"])
        )
    }

    func cursor(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private static func cursor(_ value: String) -> Int { Int(value) ?? 0 }
}

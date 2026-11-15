import Foundation

/// Endpoints used by the Files, Messages, Activity, Tasks and Settings pages.
/// Every call maps to a route in backend-contract.md (HTTP API, `/v1`). Nothing here is invented.
extension LiveHiveDataSource {
    // MARK: Reads

    func handoffs(for project: HiveProject) async throws -> [Handoff] {
        try await openWorkspaceIfNeeded(project)
        let taskResponse = try await request("tasks?include_closed=true&limit=500")
        let tasks = array(taskResponse["tasks"]).map(mapTask)
        let response = try await request("handoffs?limit=500")
        return array(response["handoffs"]).map { mapHandoff($0, tasks: tasks) }
    }

    func messages(for project: HiveProject, afterSeq: Int, limit: Int) async throws -> [HiveMessage] {
        try await openWorkspaceIfNeeded(project)
        let response = try await request("messages?after_seq=\(max(afterSeq, 0))&limit=\(min(max(limit, 1), 500))")
        return array(response["messages"]).map(mapMessage)
    }

    func activity(for project: HiveProject, afterID: Int?, limit: Int) async throws -> [ActivityEvent] {
        try await openWorkspaceIfNeeded(project)
        let bounded = min(max(limit, 1), 500)
        let path = afterID.map { "activity?after_id=\($0)&limit=\(bounded)" } ?? "activity?limit=\(bounded)"
        let response = try await request(path)
        return array(response["entries"]).map(mapActivity)
    }

    func files(for project: HiveProject, path: String, includeHidden: Bool) async throws -> FileListing {
        try await openWorkspaceIfNeeded(project)
        let response = try await request("files?path=\(Self.encode(path))&include_hidden=\(includeHidden)&limit=1000")
        return FileListing(
            path: string(response["path"]) ?? path,
            entries: array(response["entries"]).map(mapFileEntry),
            truncated: bool(response["truncated"])
        )
    }

    func fileContent(for project: HiveProject, path: String, startLine: Int, maxLines: Int) async throws -> FileContent {
        try await openWorkspaceIfNeeded(project)
        let response = try await request(
            "files/content?path=\(Self.encode(path))&start_line=\(max(startLine, 1))&max_lines=\(min(max(maxLines, 1), 10_000))"
        )
        return FileContent(
            path: string(response["path"]) ?? path,
            content: string(response["content"]) ?? "",
            sha256: string(response["sha256"]) ?? "",
            size: cursor(response["size"]),
            totalLines: cursor(response["total_lines"]),
            startLine: cursor(response["start_line"]),
            endLine: cursor(response["end_line"]),
            truncated: bool(response["truncated"]),
            nextStartLine: response["next_start_line"] is NSNull ? nil : (response["next_start_line"] as? NSNumber)?.intValue
        )
    }

    func trash(for project: HiveProject) async throws -> [TrashItem] {
        try await openWorkspaceIfNeeded(project)
        let response = try await request("trash")
        return array(response["items"]).map { item in
            TrashItem(
                trashID: string(item["trash_id"]) ?? "",
                originalPath: string(item["original_path"]) ?? "",
                kind: string(item["kind"]) ?? "file",
                entries: cursor(item["entries"]),
                deletedAt: date(item["deleted_at"]),
                deletedBy: string(item["deleted_by"]),
                reason: string(item["reason"])
            )
        }
    }

    // MARK: App-level reads

    func backendHealth() async throws -> BackendHealth {
        let basic = try await request("health")
        let details = try await request("health/details")
        let api = details["api"] as? [String: Any]
        let workspace = details["workspace"] as? [String: Any]
        let checks = workspace?["checks"] as? [String: Any]
        let database = checks?["database"] as? [String: Any]
        let folders = checks?["workspace"] as? [String: Any]
        let rawStats = workspace?["stats"] as? [String: Any] ?? [:]
        // Read into Sendable locals first: a `??` autoclosure must not capture the non-Sendable JSON dictionary.
        let basicStatus = string(basic["status"])
        let uptime = (basic["uptime_seconds"] as? NSNumber)?.doubleValue ?? 0
        let backendVersion = string(basic["backend_version"])
        let contractVersion = string(basic["contract_version"])
        return BackendHealth(
            apiStatus: string(api?["status"]) ?? basicStatus ?? "unknown",
            apiUptimeSeconds: uptime,
            backendVersion: backendVersion,
            contractVersion: contractVersion,
            workspaceOpen: bool(details["workspace_open"]),
            workspaceStatus: string(workspace?["status"]),
            databaseOK: database.map { bool($0["ok"]) },
            schemaVersion: database.map { cursor($0["schema_version"]) },
            expectedSchemaVersion: database.map { cursor($0["expected_schema_version"]) },
            workspaceFoldersOK: folders.map { bool($0["ok"]) },
            stats: rawStats.compactMapValues { ($0 as? NSNumber)?.intValue },
            processID: (workspace?["pid"] as? NSNumber)?.intValue
        )
    }

    func currentWorkspace() async throws -> WorkspaceInfo? {
        do {
            let info = try await request("workspace")
            return WorkspaceInfo(
                name: string(info["name"]) ?? "Project",
                root: string(info["root"]) ?? "",
                createdAt: optionalDate(info["created_at"]),
                schemaVersion: info["schema_version"] is NSNull ? nil : (info["schema_version"] as? NSNumber)?.intValue,
                backendVersion: string(info["backend_version"]),
                contractVersion: string(info["contract_version"]),
                projectID: string(info["id"])
            )
        } catch HiveBackendError.api(code: "NO_WORKSPACE", message: _, hint: _) {
            return nil
        }
    }

    func currentContext() async throws -> ProjectContext? {
        do {
            let response = try await request("project/context")
            let rules = response["rules"] as? [String: Any]
            return ProjectContext(
                protocolRules: string(rules?["protocol"]) ?? "",
                projectRules: array(rules?["project_rules"]).map(mapMemory),
                decisions: array(response["decisions"]).map(mapDecision),
                memory: array(response["memory"]).map(mapMemory)
            )
        } catch HiveBackendError.api(code: "NO_WORKSPACE", message: _, hint: _) {
            return nil
        }
    }

    // MARK: Writes (attributed to the user by the backend)

    func createTask(for project: HiveProject, draft: NewTaskDraft) async throws -> HiveTask {
        try await openWorkspaceIfNeeded(project)
        var body: [String: Any] = ["title": draft.title, "priority": draft.priority.rawValue]
        if !draft.details.isEmpty { body["description"] = draft.details }
        if !draft.labels.isEmpty { body["labels"] = draft.labels }
        if !draft.dependsOn.isEmpty { body["depends_on"] = draft.dependsOn }
        let response = try await request("tasks", method: "POST", body: body)
        return try requireTask(response)
    }

    func cancelTask(for project: HiveProject, taskID: String, reason: String) async throws -> HiveTask {
        try await openWorkspaceIfNeeded(project)
        let response = try await request("tasks/\(Self.encode(taskID))/cancel", method: "POST", body: ["reason": reason])
        return try requireTask(response)
    }

    func releaseTask(for project: HiveProject, taskID: String) async throws -> HiveTask {
        try await openWorkspaceIfNeeded(project)
        let response = try await request("tasks/\(Self.encode(taskID))/release", method: "POST")
        return try requireTask(response)
    }

    func sendMessage(for project: HiveProject, draft: NewMessageDraft) async throws -> HiveMessage {
        try await openWorkspaceIfNeeded(project)
        var body: [String: Any] = ["to": draft.to, "body": draft.body, "kind": draft.kind.rawValue]
        if let subject = draft.subject, !subject.isEmpty { body["subject"] = subject }
        if let taskID = draft.taskID, !taskID.isEmpty { body["task_id"] = taskID }
        let response = try await request("messages", method: "POST", body: body)
        guard let message = response["message"] as? [String: Any] else { throw HiveBackendError.invalidResponse }
        return mapMessage(message)
    }

    func restoreTrashItem(for project: HiveProject, trashID: String) async throws {
        try await openWorkspaceIfNeeded(project)
        _ = try await request("trash/\(Self.encode(trashID))/restore", method: "POST")
    }

    func removeAgent(for project: HiveProject, agentID: String) async throws {
        try await openWorkspaceIfNeeded(project)
        _ = try await request("agents/\(Self.encode(agentID))/remove", method: "POST")
    }

    // MARK: Mapping

    func mapMessage(_ value: [String: Any]) -> HiveMessage {
        HiveMessage(
            id: string(value["id"]) ?? UUID().uuidString,
            seq: cursor(value["seq"]),
            threadID: string(value["thread_id"]),
            kind: HiveMessage.Kind(rawValue: string(value["kind"]) ?? "") ?? .message,
            fromID: string(value["from_id"]),
            fromName: string(value["from_name"]) ?? "Unknown",
            fromKind: string(value["from_kind"]) ?? "agent",
            toID: string(value["to_id"]),
            toName: string(value["to_name"]),
            subject: string(value["subject"]),
            body: string(value["body"]) ?? "",
            taskID: string(value["task_id"]),
            createdAt: date(value["created_at"])
        )
    }

    func mapFileEntry(_ value: [String: Any]) -> FileEntry {
        let type = string(value["type"]) ?? "other"
        let kind: FileEntry.Kind = switch type {
        case "file": .file
        case "dir": .directory
        case "symlink": .symlink
        default: .other
        }
        return FileEntry(
            name: string(value["name"]) ?? "",
            path: string(value["path"]) ?? "",
            kind: kind,
            size: (value["size"] as? NSNumber)?.intValue,
            modified: optionalDate(value["modified"])
        )
    }

    func mapMemory(_ value: [String: Any]) -> MemoryEntry {
        MemoryEntry(
            id: string(value["id"]) ?? UUID().uuidString,
            key: string(value["key"]) ?? "",
            category: string(value["category"]) ?? "general",
            value: string(value["value"]) ?? "",
            tags: strings(value["tags"]),
            version: max(cursor(value["version"]), 1),
            updatedByName: string(value["updated_by_name"]),
            updatedAt: date(value["updated_at"])
        )
    }

    func mapDecision(_ value: [String: Any]) -> DecisionRecord {
        DecisionRecord(
            id: string(value["id"]) ?? UUID().uuidString,
            title: string(value["title"]) ?? "",
            decision: string(value["decision"]) ?? "",
            rationale: string(value["rationale"]),
            tags: strings(value["tags"]),
            status: string(value["status"]) ?? "active",
            decidedByName: string(value["decided_by_name"]),
            createdAt: date(value["created_at"])
        )
    }

    private func requireTask(_ response: [String: Any]) throws -> HiveTask {
        guard let task = response["task"] as? [String: Any] else { throw HiveBackendError.invalidResponse }
        return mapTask(task)
    }

    /// Percent-encodes one query value or path segment (leaves only unreserved characters).
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension LiveHiveDataSource {
    func onboarding(for project: HiveProject, setup: AgentSetupRequest) async throws -> AgentOnboarding {
        // Make sure the backend has THIS project open, then let it verify the id as a second line of defence.
        try await openWorkspaceIfNeeded(project)
        var body: [String: Any] = ["agent_name": setup.name, "client": setup.client.rawValue]
        if !setup.role.isEmpty { body["role"] = setup.role }
        if !setup.capabilities.isEmpty { body["capabilities"] = setup.capabilities }
        if let projectID = project.projectID { body["project_id"] = projectID }
        let response = try await request("onboarding/prompt", method: "POST", body: body)
        guard let prompt = string(response["prompt"]) else { throw HiveBackendError.invalidResponse }
        let info = response["project"] as? [String: Any]
        return AgentOnboarding(
            prompt: prompt,
            projectID: string(info?["id"]) ?? project.projectID ?? "",
            projectName: string(info?["name"]) ?? project.name,
            warnings: strings(response["warnings"])
        )
    }
}

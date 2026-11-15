import Foundation

/// The UI's only window onto the Hive backend.
///
/// Every member maps to an endpoint in backend-contract.md (HTTP API, `/v1`). The live implementation
/// (`LiveHiveDataSource`) talks to the bundled local API; `MockHiveDataSource` serves fabricated data for
/// previews, tests and `--hive-mock` runs.
protocol HiveDataSource: Sendable {
    /// True while the data is fabricated for UI development.
    var isPreviewData: Bool { get }

    // MARK: Project lifecycle and dashboard

    func inspectProject(at url: URL) async throws -> ProjectInspection
    func initializeProject(at url: URL) async throws -> HiveProject
    func snapshot(for project: HiveProject) async throws -> ProjectSnapshot

    /// Live activity for the open project. Finishes when the consumer stops iterating.
    func events(for project: HiveProject) -> AsyncStream<ActivityEvent>

    // MARK: Reads for the pages

    /// `GET /v1/handoffs`: every status, newest first.
    func handoffs(for project: HiveProject) async throws -> [Handoff]

    /// `GET /v1/messages`: up to `limit` messages with `seq` greater than `afterSeq`, oldest first.
    func messages(for project: HiveProject, afterSeq: Int, limit: Int) async throws -> [HiveMessage]

    /// `GET /v1/activity`. With `afterID` it returns newer events oldest first; without it, the newest `limit`
    /// events. Both are returned oldest first.
    func activity(for project: HiveProject, afterID: Int?, limit: Int) async throws -> [ActivityEvent]

    /// `GET /v1/files`: one directory, not recursive.
    func files(for project: HiveProject, path: String, includeHidden: Bool) async throws -> FileListing

    /// `GET /v1/files/content`: a page of a UTF-8 text file.
    func fileContent(for project: HiveProject, path: String, startLine: Int, maxLines: Int) async throws -> FileContent

    /// `GET /v1/trash`.
    func trash(for project: HiveProject) async throws -> [TrashItem]

    // MARK: App-level reads (used by Settings; no project required)

    /// `GET /v1/health` and `GET /v1/health/details`.
    func backendHealth() async throws -> BackendHealth

    /// `GET /v1/workspace`. Nil when no workspace is open.
    func currentWorkspace() async throws -> WorkspaceInfo?

    /// `GET /v1/project/context`. Nil when no workspace is open.
    func currentContext() async throws -> ProjectContext?

    // MARK: Writes the HTTP API offers the user (attributed to the user by the backend)

    /// `POST /v1/tasks`.
    func createTask(for project: HiveProject, draft: NewTaskDraft) async throws -> HiveTask

    /// `POST /v1/tasks/{id}/cancel`.
    func cancelTask(for project: HiveProject, taskID: String, reason: String) async throws -> HiveTask

    /// `POST /v1/tasks/{id}/release`: frees a task held by an agent so another agent can claim it.
    func releaseTask(for project: HiveProject, taskID: String) async throws -> HiveTask

    /// `POST /v1/messages`.
    func sendMessage(for project: HiveProject, draft: NewMessageDraft) async throws -> HiveMessage

    /// `POST /v1/trash/{trash_id}/restore`.
    func restoreTrashItem(for project: HiveProject, trashID: String) async throws

    /// `POST /v1/agents/{agent_id}/remove`: removes an agent from the project. Its sessions end, any tasks it
    /// holds return to the backlog, and it can no longer reconnect. Its history is preserved.
    func removeAgent(for project: HiveProject, agentID: String) async throws

    // MARK: Set Up Agent

    /// `POST /v1/onboarding/prompt`: the complete onboarding instruction for one agent in `project`.
    /// The backend refuses (PROJECT_MISMATCH) if the open workspace is not `project`.
    func onboarding(for project: HiveProject, setup: AgentSetupRequest) async throws -> AgentOnboarding
}

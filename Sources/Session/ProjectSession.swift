import Foundation
import Observation

/// State for one window: which project is open, what it contains, and what is selected.
/// All backend access goes through `dataSource`; views never talk to the backend directly.
@MainActor @Observable
final class ProjectSession {
    struct PendingFolder: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
    }

    enum LoadState {
        case idle, loading, loaded, failed(String)
    }

    let dataSource: any HiveDataSource
    let recents: RecentProjects

    private(set) var project: HiveProject?
    private(set) var snapshot: ProjectSnapshot?
    private(set) var loadState: LoadState = .idle
    private(set) var isOpening = false
    private(set) var isInitializing = false

    var selection: SidebarItem = .dashboard
    var isShowingImporter = false
    var pendingInitialization: PendingFolder?
    var initializationError: String?
    var errorMessage: String?

    // Page models. Created once per window and bound to the project when it opens.
    let messages = MessagesModel()
    let handoffs = HandoffsModel()
    let activity = ActivityModel()
    let files = FilesModel()

    /// Set when a row elsewhere asks a page to show a specific item (for example, a Dashboard task row).
    /// The page applies it and clears it.
    var focusedTaskID: HiveTask.ID?
    var focusedAgentID: Agent.ID?

    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    private static let activityLimit = 50
    private static let reloadDelay: Duration = .milliseconds(700)

    init(dataSource: any HiveDataSource, recents: RecentProjects) {
        self.dataSource = dataSource
        self.recents = recents
    }

    // MARK: - Opening

    func openFolder(_ url: URL) async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }

        close()
        // Returns false when the URL isn't security-scoped (e.g. an unsandboxed debug build).
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }

        do {
            switch try await dataSource.inspectProject(at: url) {
            case .initialized(let project):
                await activate(project)
            case .notInitialized:
                initializationError = nil
                pendingInitialization = PendingFolder(url: url)
            }
        } catch {
            releaseScopedAccess()
            errorMessage = error.localizedDescription
        }
    }

    func openRecent(_ recent: RecentProject) async {
        do {
            let url = try recents.resolveURL(for: recent)
            await openFolder(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Initializing

    func initializeProject(_ pending: PendingFolder) async {
        guard !isInitializing else { return }
        isInitializing = true
        defer { isInitializing = false }
        initializationError = nil

        do {
            let project = try await dataSource.initializeProject(at: pending.url)
            pendingInitialization = nil
            await activate(project)
        } catch {
            initializationError = error.localizedDescription
        }
    }

    /// Called whenever the initialization sheet goes away. If no project opened, drop folder access.
    func initializationSheetDismissed() {
        if project == nil {
            releaseScopedAccess()
        }
    }

    // MARK: - Lifecycle

    /// Reloads the project snapshot. A `quiet` reload (used for live updates) never raises an alert.
    func reload(quiet: Bool = false) async {
        guard let project else { return }
        if snapshot == nil { loadState = .loading }
        do {
            let fresh = try await dataSource.snapshot(for: project)
            guard self.project?.id == project.id else { return }
            snapshot = fresh
            activity.receive(contentsOf: fresh.activity)
            loadState = .loaded
        } catch {
            if snapshot == nil {
                loadState = .failed(error.localizedDescription)
            } else if !quiet {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Reloads the snapshot and every page that has already loaded (the toolbar's Refresh and ⌘R).
    func reloadAll() async {
        await reload()
        if messages.phase == .loaded { await messages.reload() }
        if handoffs.phase == .loaded { await handoffs.reload() }
        if activity.phase == .loaded { await activity.reload() }
        if files.rootPhase == .loaded { await files.refreshAfterChange() }
    }

    func close() {
        eventTask?.cancel()
        eventTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        project = nil
        snapshot = nil
        loadState = .idle
        selection = .dashboard
        focusedTaskID = nil
        focusedAgentID = nil
        messages.reset()
        handoffs.reset()
        activity.reset()
        files.reset()
        releaseScopedAccess()
    }

    // MARK: - Actions the backend offers the user

    @discardableResult
    func createTask(_ draft: NewTaskDraft) async throws -> HiveTask {
        let project = try requireProject()
        let task = try await dataSource.createTask(for: project, draft: draft)
        await reload(quiet: true)
        return task
    }

    func cancelTask(_ task: HiveTask, reason: String) async throws {
        let project = try requireProject()
        _ = try await dataSource.cancelTask(for: project, taskID: task.id, reason: reason)
        await reload(quiet: true)
    }

    func releaseTask(_ task: HiveTask) async throws {
        let project = try requireProject()
        _ = try await dataSource.releaseTask(for: project, taskID: task.id)
        await reload(quiet: true)
    }

    func removeAgent(_ agent: Agent) async throws {
        let project = try requireProject()
        try await dataSource.removeAgent(for: project, agentID: agent.id)
        await reload(quiet: true)
    }

    // MARK: - Navigation helpers

    func showTask(_ id: HiveTask.ID) {
        focusedTaskID = id
        selection = .tasks
    }

    func showAgent(_ id: Agent.ID) {
        focusedAgentID = id
        selection = .agents
    }

    // MARK: - Private

    private func requireProject() throws -> HiveProject {
        guard let project else { throw HiveBackendError.serviceUnavailable("No project is open.") }
        return project
    }

    private func activate(_ project: HiveProject) async {
        self.project = project
        selection = .dashboard
        let context = DataContext(dataSource: dataSource, project: project)
        messages.bind(context)
        handoffs.bind(context)
        activity.bind(context)
        files.bind(context)
        recents.record(project)
        await reload()
        startListening(to: project)
    }

    private func startListening(to project: HiveProject) {
        eventTask?.cancel()
        let stream = dataSource.events(for: project)
        eventTask = Task { [weak self] in
            for await event in stream {
                self?.receive(event)
            }
        }
    }

    private func receive(_ event: ActivityEvent) {
        guard var current = snapshot else { return }
        // A reload may already have picked this event up (for example after the user's own action).
        // Only the snapshot insert is de-duplicated: the Activity page and the routing below must still see it.
        if !current.activity.contains(where: { $0.id == event.id }) {
            current.activity.insert(event, at: 0)
            if current.activity.count > Self.activityLimit {
                current.activity.removeLast(current.activity.count - Self.activityLimit)
            }
            snapshot = current
        }

        activity.receive(event)
        route(event)
    }

    /// Sends a live event to whichever page data it affects.
    private func route(_ event: ActivityEvent) {
        let action = event.action
        if action.hasPrefix("message.") || event.kind == .message {
            Task { await messages.refresh() }
        }
        if action.hasPrefix("handoff.") {
            Task { await handoffs.refresh() }
        }
        if action.hasPrefix("file.") || action.hasPrefix("folder.") {
            Task { await files.refreshAfterChange() }
        } else {
            scheduleSnapshotReload()
        }
    }

    /// Agents, tasks and the Dashboard come from the snapshot, so reload it shortly after activity settles.
    private func scheduleSnapshotReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reloadDelay)
            guard !Task.isCancelled else { return }
            await self?.reload(quiet: true)
        }
    }

    private func releaseScopedAccess() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}

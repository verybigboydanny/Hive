import Foundation

/// The open workspace (`GET /v1/workspace`).
struct WorkspaceInfo: Hashable, Sendable {
    var name: String
    var root: String
    var createdAt: Date?
    var schemaVersion: Int?
    var backendVersion: String?
    var contractVersion: String?
    /// The stable project id (`prj_…`).
    var projectID: String? = nil
}

/// Backend and workspace health (`GET /v1/health` and `GET /v1/health/details`).
struct BackendHealth: Hashable, Sendable {
    var apiStatus: String
    var apiUptimeSeconds: Double
    var backendVersion: String?
    var contractVersion: String?
    var workspaceOpen: Bool
    /// ok or degraded, when a workspace is open.
    var workspaceStatus: String?
    var databaseOK: Bool?
    var schemaVersion: Int?
    var expectedSchemaVersion: Int?
    var workspaceFoldersOK: Bool?
    /// agents, open_sessions, pending_handoffs, open_tasks, expired_leases.
    var stats: [String: Int]
    var processID: Int?
}

struct GitSummary: Hashable, Sendable {
    var branch: String?
    var head: String?
    var dirtyFiles: Int?
}

/// Project-level numbers from `GET /v1/project/status` that the Dashboard shows.
struct ProjectOverview: Hashable, Sendable {
    var expiredLeases = 0
    var totalMessages = 0
    var memoryEntries = 0
    var activeDecisions = 0
    var git: GitSummary? = nil
    var createdAt: Date? = nil
}

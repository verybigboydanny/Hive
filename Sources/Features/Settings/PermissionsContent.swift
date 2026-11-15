import Foundation

/// The access rules and limits Hive enforces. All of it is read-only in the app: the backend has no per-agent
/// permission settings and no endpoint to read or change limits. Values are the backend's own defaults
/// (`settings.py`, `services/files.py`), checked against the source rather than written from memory.
enum PermissionsContent {
    struct Rule: Identifiable, Sendable {
        let title: String
        let detail: String
        let symbol: String
        var id: String { title }
    }

    struct Limit: Identifiable, Sendable {
        let name: String
        let value: String
        /// True when a project can override it with `settings` in `.hive/config.json`.
        let isOverridable: Bool
        var id: String { name }
    }

    static let rules: [Rule] = [
        Rule(title: "All agents have the same access",
             detail: "Hive has no per-agent permission settings. Every registered agent can use the same tools, and what it may touch is limited by the rules below.",
             symbol: "person.2"),
        Rule(title: "Files stay inside the project",
             detail: "Agents use paths relative to the project. Paths that leave the project, and the .hive and .git folders, are refused. Folder listings leave out node_modules, __pycache__ and DerivedData.",
             symbol: "folder.badge.minus"),
        Rule(title: "Changing a file needs its latest version",
             detail: "To overwrite a file, an agent must pass the checksum (sha256) of the version it last read. If someone else changed it, the write fails with a conflict instead of overwriting.",
             symbol: "doc.badge.gearshape"),
        Rule(title: "Deleting is recoverable",
             detail: "Deleting needs an explicit confirmation and a reason, and moves the item to Hive's trash. You can restore it from the Files page.",
             symbol: "trash"),
        Rule(title: "Tasks are claimed for a limited time",
             detail: "An agent claims a task for a lease that its activity renews. Only the owner updates or completes it. When a claim expires, another agent can take the task over. The owner, the creator or you can cancel it.",
             symbol: "checklist"),
        Rule(title: "Handoffs go to the right agent",
             detail: "A handoff addressed to a specific agent can only be accepted by that agent. Only the sender or you can cancel it.",
             symbol: "arrow.left.arrow.right"),
        Rule(title: "An agent keeps its identity",
             detail: "To reconnect as the same agent, Claude must present the agent ID together with its resume token. The token is shown once, when the agent registers.",
             symbol: "key"),
        Rule(title: "What you can do from this app",
             detail: "Create tasks, release or cancel them, send messages, and restore deleted files. Everything else is done by agents through the MCP server.",
             symbol: "person.crop.circle")
    ]

    static let limits: [Limit] = [
        Limit(name: "Active tasks per agent", value: "5", isOverridable: true),
        Limit(name: "Agents per project", value: "200", isOverridable: true),
        Limit(name: "Task claim lease", value: "30 minutes (up to 240)", isOverridable: true),
        Limit(name: "Task stays reserved for a pending handoff", value: "24 hours", isOverridable: true),
        Limit(name: "Agent counts as online", value: "active in the last 2 minutes", isOverridable: true),
        Limit(name: "Agent counts as away", value: "active in the last 15 minutes", isOverridable: true),
        Limit(name: "Text fields, messages and memory values", value: "20,000 characters each", isOverridable: true),
        Limit(name: "Checkpoint state", value: "64 KB", isOverridable: false),
        Limit(name: "File read", value: "2 MiB", isOverridable: false),
        Limit(name: "File write", value: "5 MiB", isOverridable: false),
        Limit(name: "Folder listing", value: "1,000 entries, 10 levels deep", isOverridable: false),
        Limit(name: "Recursive delete", value: "2,000 entries", isOverridable: false)
    ]
}

import Foundation

/// One item of a directory listing (`GET /v1/files`).
struct FileEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case file, directory, symlink, other
    }

    var id: String { path }
    var name: String
    /// Workspace-relative, `/`-separated.
    var path: String
    var kind: Kind
    var size: Int?
    var modified: Date?
}

struct FileListing: Hashable, Sendable {
    var path: String
    var entries: [FileEntry]
    var truncated: Bool
}

/// A page of a text file (`GET /v1/files/content`).
struct FileContent: Hashable, Sendable {
    var path: String
    var content: String
    var sha256: String
    var size: Int
    var totalLines: Int
    var startLine: Int
    var endLine: Int
    var truncated: Bool
    var nextStartLine: Int?
}

/// A recoverable deletion (`GET /v1/trash`).
struct TrashItem: Identifiable, Hashable, Sendable {
    var id: String { trashID }
    var trashID: String
    var originalPath: String
    var kind: String
    var entries: Int
    var deletedAt: Date
    var deletedBy: String?
    var reason: String?
}

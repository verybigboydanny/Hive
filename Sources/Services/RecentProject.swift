import Foundation

/// A project the user opened before. The bookmark restores sandboxed access to the folder.
struct RecentProject: Identifiable, Codable, Hashable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var bookmark: Data
    var lastOpened: Date
}

import Foundation
import Observation
import os

enum RecentProjectError: LocalizedError {
    case folderMissing(String)

    var errorDescription: String? {
        switch self {
        case .folderMissing(let path):
            return "Hive can't find the project folder at \(path). It may have been moved or deleted. Remove it from Recents and open it again with Open Project Folder…"
        }
    }
}

/// Remembers recently opened project folders using bookmarks,
/// stored in a file in Application Support (not UserDefaults).
///
/// A bookmark can fail to resolve with "the file isn't in the correct format" when it was made by a differently
/// signed or sandboxed build of the app (for example a debug build versus a release build). Resolving therefore
/// falls back from a security-scoped bookmark to a plain one, and finally to the stored path.
@MainActor @Observable
final class RecentProjects {
    private(set) var items: [RecentProject] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Hive",
        category: "RecentProjects"
    )

    private static let limit = 10

    /// - Parameter fileURL: Override the storage location (used by tests). Defaults to Application Support.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "Hive", directoryHint: .isDirectory)
            .appending(path: "recent-projects.json")
        load()
    }

    func record(_ project: HiveProject) {
        insert(name: project.name, url: project.rootURL)
    }

    func remove(_ recent: RecentProject) {
        items.removeAll { $0.id == recent.id }
        save()
    }

    /// Returns a folder URL for the recent project, or throws a readable error when the folder is gone.
    func resolveURL(for recent: RecentProject) throws -> URL {
        for options in [URL.BookmarkResolutionOptions.withSecurityScope, []] where !recent.bookmark.isEmpty {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: recent.bookmark,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale { insert(name: recent.name, url: url) }
                return url
            }
        }

        // The bookmark could not be read: use the remembered path if the folder is still there.
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: recent.path, isDirectory: &isDirectory), isDirectory.boolValue {
            logger.notice("Bookmark for \(recent.path, privacy: .public) was unreadable; using the stored path.")
            let url = URL(fileURLWithPath: recent.path, isDirectory: true)
            insert(name: recent.name, url: url)
            return url
        }
        throw RecentProjectError.folderMissing(recent.path)
    }

    private func insert(name: String, url: URL) {
        let entry = RecentProject(
            name: name,
            path: url.path,
            bookmark: Self.makeBookmark(for: url, logger: logger),
            lastOpened: .now
        )
        items.removeAll { $0.id == entry.id }
        items.insert(entry, at: 0)
        items = Array(items.prefix(Self.limit))
        save()
    }

    /// A security-scoped bookmark when possible, otherwise a plain one, otherwise empty (the path is the fallback).
    private static func makeBookmark(for url: URL, logger: Logger) -> Data {
        for options in [URL.BookmarkCreationOptions.withSecurityScope, []] {
            do {
                return try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch {
                logger.error("Couldn't bookmark project: \(error.localizedDescription)")
            }
        }
        return Data()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([RecentProject].self, from: data)
        } catch {
            logger.error("Couldn't load recent projects: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Couldn't save recent projects: \(error.localizedDescription)")
        }
    }
}

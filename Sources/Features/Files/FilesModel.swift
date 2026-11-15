import Foundation
import Observation

/// One visible row of the file tree.
struct FileRow: Identifiable, Hashable, Sendable {
    let entry: FileEntry
    let depth: Int
    let isExpanded: Bool
    let isLoading: Bool
    var id: String { entry.id }
}

/// Read-only browser over the project's files (`GET /v1/files`, `GET /v1/files/content`) plus the trash.
/// Folders load lazily when expanded.
@MainActor @Observable
final class FilesModel {
    enum ContentState: Equatable {
        case none
        case loading
        case loaded
        /// The file can't be previewed (not UTF-8 text, or too large). Not an error.
        case unavailable(String)
        case failed(String)
    }

    private static let rootKey = "."
    private static let firstPageLines = 2_000
    private static let morePageLines = 2_000

    private(set) var listings: [String: FileListing] = [:]
    private(set) var expanded: Set<String> = []
    private(set) var loadingPaths: Set<String> = []
    private(set) var rootPhase: LoadPhase = .idle
    private(set) var includeHidden = false

    private(set) var selectedPath: String?
    private(set) var contentState: ContentState = .none
    private(set) var lines: [String] = []
    /// `lines` with a stable id (the 1-based line number) for the preview's ForEach.
    private(set) var numberedLines: [NumberedLine] = []
    private(set) var fileInfo: FileContent?
    private(set) var isLoadingMore = false

    private(set) var trash: [TrashItem] = []
    private(set) var trashError: String?

    @ObservationIgnored private var context: DataContext?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshQueued = false

    // MARK: Lifecycle

    func bind(_ context: DataContext) {
        reset()
        self.context = context
    }

    func reset() {
        context = nil
        listings = [:]
        expanded = []
        loadingPaths = []
        rootPhase = .idle
        selectedPath = nil
        contentState = .none
        setLines([])
        fileInfo = nil
        isLoadingMore = false
        trash = []
        trashError = nil
        refreshQueued = false
    }

    // MARK: Tree

    var rows: [FileRow] {
        var result: [FileRow] = []
        appendRows(for: Self.rootKey, depth: 0, into: &result)
        return result
    }

    var rootTruncated: Bool { listings[Self.rootKey]?.truncated ?? false }

    private func appendRows(for key: String, depth: Int, into result: inout [FileRow]) {
        guard let listing = listings[key] else { return }
        let sorted = listing.entries.sorted { lhs, rhs in
            if (lhs.kind == .directory) != (rhs.kind == .directory) { return lhs.kind == .directory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        for entry in sorted {
            let isOpen = entry.kind == .directory && expanded.contains(entry.path)
            result.append(FileRow(entry: entry, depth: depth, isExpanded: isOpen, isLoading: loadingPaths.contains(entry.path)))
            if isOpen { appendRows(for: entry.path, depth: depth + 1, into: &result) }
        }
    }

    func loadRootIfNeeded() async {
        guard rootPhase == .idle else { return }
        await loadRoot()
    }

    func loadRoot() async {
        guard let context else { return }
        rootPhase = .loading
        do {
            listings[Self.rootKey] = try await context.dataSource.files(for: context.project, path: ".", includeHidden: includeHidden)
            rootPhase = .loaded
        } catch {
            rootPhase = .failed(error.localizedDescription)
        }
    }

    func toggle(_ entry: FileEntry) async {
        guard entry.kind == .directory, let context else { return }
        if expanded.contains(entry.path) {
            expanded.remove(entry.path)
            return
        }
        expanded.insert(entry.path)
        guard listings[entry.path] == nil else { return }
        loadingPaths.insert(entry.path)
        defer { loadingPaths.remove(entry.path) }
        do {
            listings[entry.path] = try await context.dataSource.files(for: context.project, path: entry.path, includeHidden: includeHidden)
        } catch {
            expanded.remove(entry.path)
        }
    }

    func setIncludeHidden(_ value: Bool) async {
        guard value != includeHidden else { return }
        includeHidden = value
        listings = [:]
        expanded = []
        await loadRoot()
    }

    // MARK: Bindings for views

    /// The tree's selection. Choosing a folder expands or collapses it; choosing a file previews it.
    var selectionID: String? {
        get { selectedPath }
        set {
            guard let newValue else {
                Task { await select(nil) }
                return
            }
            Task { await activate(path: newValue) }
        }
    }

    var showsHidden: Bool {
        get { includeHidden }
        set { Task { await setIncludeHidden(newValue) } }
    }

    func activate(path: String) async {
        let entry = listings.values.lazy.flatMap(\.entries).first { $0.path == path }
        if let entry, entry.kind == .directory {
            await toggle(entry)
        } else {
            await select(path)
        }
    }

    // MARK: Preview

    func select(_ path: String?) async {
        guard let path else {
            selectedPath = nil
            contentState = .none
            setLines([])
            fileInfo = nil
            return
        }
        guard path != selectedPath, let context else { return }
        selectedPath = path
        contentState = .loading
        setLines([])
        fileInfo = nil
        do {
            let page = try await context.dataSource.fileContent(
                for: context.project, path: path, startLine: 1, maxLines: Self.firstPageLines
            )
            guard selectedPath == path else { return }
            setLines(Self.splitLines(page.content))
            fileInfo = page
            contentState = .loaded
        } catch {
            guard selectedPath == path else { return }
            contentState = Self.state(for: error)
        }
    }

    func loadMoreLines() async {
        guard let context, let path = selectedPath, let next = fileInfo?.nextStartLine, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await context.dataSource.fileContent(
                for: context.project, path: path, startLine: next, maxLines: Self.morePageLines
            )
            guard selectedPath == path else { return }
            setLines(lines + Self.splitLines(page.content))
            fileInfo = page
        } catch {
            guard selectedPath == path else { return }
            contentState = Self.state(for: error)
        }
    }

    /// Called when file activity arrives. Re-reads the folders already shown and the open file.
    func refreshAfterChange() async {
        guard rootPhase == .loaded, let context else { return }
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshQueued = false
            for key in listings.keys.sorted() {
                let path = key
                if let fresh = try? await context.dataSource.files(for: context.project, path: path, includeHidden: includeHidden) {
                    listings[key] = fresh
                } else if key != Self.rootKey {
                    listings[key] = nil
                    expanded.remove(key)
                }
            }
            if let path = selectedPath {
                let wanted = max(lines.count, Self.firstPageLines)
                if let page = try? await context.dataSource.fileContent(for: context.project, path: path, startLine: 1, maxLines: wanted),
                   selectedPath == path {
                    setLines(Self.splitLines(page.content))
                    fileInfo = page
                    contentState = .loaded
                }
            }
        } while refreshQueued
    }

    // MARK: Trash

    func loadTrash() async {
        guard let context else { return }
        do {
            trash = try await context.dataSource.trash(for: context.project)
            trashError = nil
        } catch {
            trashError = error.localizedDescription
        }
    }

    func restore(_ item: TrashItem) async throws {
        guard let context else { throw HiveBackendError.serviceUnavailable("No project is open.") }
        try await context.dataSource.restoreTrashItem(for: context.project, trashID: item.trashID)
        await loadTrash()
        await refreshAfterChange()
    }

    // MARK: Helpers

    private func setLines(_ newLines: [String]) {
        lines = newLines
        numberedLines = newLines.enumerated().map { NumberedLine(id: $0.offset + 1, text: $0.element) }
    }

    /// Splits on any newline, including `\r\n` (which Swift treats as one Character), and drops the empty
    /// element a trailing newline would produce.
    static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var parts = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    private static func state(for error: Error) -> ContentState {
        if case HiveBackendError.api(let code, let message, _) = error {
            switch code {
            case "NOT_TEXT": return .unavailable("This file isn't UTF-8 text, so Hive can't preview it.")
            case "FILE_TOO_LARGE": return .unavailable("This file is larger than Hive's read limit, so it can't be previewed.")
            default: return .failed(message)
            }
        }
        return .failed(error.localizedDescription)
    }
}

import Foundation

/// Result of looking at a folder the user picked.
enum ProjectInspection: Sendable {
    case initialized(HiveProject)
    case notInitialized
}

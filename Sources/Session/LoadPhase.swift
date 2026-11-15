import Foundation

/// Where a page's data is in its lifecycle.
enum LoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// What a page model needs to reach the backend for the open project.
struct DataContext: Sendable {
    let dataSource: any HiveDataSource
    let project: HiveProject
}

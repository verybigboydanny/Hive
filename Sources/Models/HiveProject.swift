import Foundation

/// PROVISIONAL: UI-side shape. Reconcile with docs/backend-contract.md.
struct HiveProject: Identifiable, Hashable, Sendable {
    enum Status: Sendable {
        case ready, attention, disconnected
    }

    var id: URL { rootURL }
    var name: String
    var rootURL: URL
    var status: Status
    /// The stable backend project id (`prj_…`). Nil only for projects created by mock data.
    var projectID: String? = nil
}

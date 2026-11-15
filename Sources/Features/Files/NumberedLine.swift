import Foundation

/// One line of a file preview. The id is the 1-based line number.
struct NumberedLine: Identifiable, Hashable, Sendable {
    let id: Int
    let text: String
}

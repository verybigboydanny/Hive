import Foundation

extension FileEntry.Kind {
    var symbol: String {
        switch self {
        case .directory: "folder"
        case .file: "doc"
        case .symlink: "link"
        case .other: "questionmark.square.dashed"
        }
    }
}

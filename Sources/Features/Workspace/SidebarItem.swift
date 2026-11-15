import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, files, agents, setUpAgent, tasks, messages, activity, guide

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: "Dashboard"
        case .files: "Files"
        case .agents: "Agents"
        case .setUpAgent: "Set Up Agent"
        case .tasks: "Tasks"
        case .messages: "Messages"
        case .activity: "Activity"
        case .guide: "How to use Hive"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .files: "folder"
        case .agents: "person.2"
        case .setUpAgent: "person.badge.plus"
        case .tasks: "checklist"
        case .messages: "bubble.left.and.bubble.right"
        case .activity: "clock.arrow.circlepath"
        case .guide: "book.closed"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .dashboard: "1"
        case .files: "2"
        case .agents: "3"
        case .tasks: "4"
        case .messages: "5"
        case .activity: "6"
        case .guide: "7"
        case .setUpAgent: "8"
        }
    }
}

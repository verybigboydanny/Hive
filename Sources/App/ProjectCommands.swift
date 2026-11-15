import SwiftUI

struct ProjectCommands: Commands {
    @FocusedValue(\.projectSession) private var session

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Project Folder…") {
                session?.isShowingImporter = true
            }
            .keyboardShortcut("o")
            .disabled(session == nil)

            Button("Close Project") {
                session?.close()
            }
            .keyboardShortcut("w", modifiers: [.command, .control])
            .disabled(session?.project == nil)
        }

        CommandMenu("Project") {
            Button("Refresh") {
                Task { await session?.reloadAll() }
            }
            .keyboardShortcut("r")
            .disabled(session?.project == nil)

            Divider()

            ForEach(SidebarItem.allCases) { item in
                Button(item.title) {
                    session?.selection = item
                }
                .keyboardShortcut(item.shortcut)
                .disabled(session?.project == nil)
            }
        }
    }
}

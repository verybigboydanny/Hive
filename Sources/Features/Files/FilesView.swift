import SwiftUI

/// Read-only browser over the project's files, plus the recoverable trash.
struct FilesView: View {
    @Environment(ProjectSession.self) private var session
    @State private var showsTrash = false

    var body: some View {
        @Bindable var files = session.files
        FilesContent()
            .toolbar {
                ToolbarItem {
                    Toggle("Show Hidden Files", systemImage: "eye", isOn: $files.showsHidden)
                        .help("Show files whose names start with a dot")
                }
                ToolbarItem {
                    Button("Trash", systemImage: "trash") {
                        showsTrash = true
                    }
                    .help("Files agents deleted. They can be restored.")
                }
            }
            .sheet(isPresented: $showsTrash) {
                TrashSheet()
            }
            .task {
                await session.files.loadRootIfNeeded()
            }
    }
}

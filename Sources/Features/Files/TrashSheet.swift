import SwiftUI

/// Files agents deleted. Restoring puts an item back where it was.
struct TrashSheet: View {
    @Environment(ProjectSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var restoringID: String?
    @State private var errorMessage: String?

    var body: some View {
        let files = session.files
        VStack(spacing: 0) {
            Text("Trash")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HiveMetrics.spacingLoose)
            Divider()
            if files.trash.isEmpty {
                ContentUnavailableView(
                    "Trash Is Empty",
                    systemImage: "trash",
                    description: Text("When an agent deletes a file or folder it goes here first, so it can be restored.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(files.trash) { item in
                    TrashRow(item: item, isRestoring: restoringID == item.id) {
                        restore(item)
                    }
                }
            }
            if let message = errorMessage ?? files.trashError {
                InlineErrorView(message: message)
                    .padding(HiveMetrics.spacing)
            }
            Divider()
            HStack {
                Text("Restoring fails if something already exists at the original path.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(HiveMetrics.spacing)
        }
        .frame(width: HiveMetrics.formSheetWidth, height: HiveMetrics.sheetHeight)
        .task {
            await session.files.loadTrash()
        }
    }

    private func restore(_ item: TrashItem) {
        restoringID = item.id
        errorMessage = nil
        Task {
            do {
                try await session.files.restore(item)
            } catch {
                errorMessage = error.localizedDescription
            }
            restoringID = nil
        }
    }
}

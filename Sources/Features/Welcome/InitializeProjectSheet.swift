import SwiftUI

struct InitializeProjectSheet: View {
    @Environment(ProjectSession.self) private var session
    let pending: ProjectSession.PendingFolder

    var body: some View {
        VStack(spacing: 16) {
            HiveLogo(size: HiveMetrics.sheetLogoSize)

            VStack(spacing: 4) {
                Text("Initialize Hive in “\(pending.url.lastPathComponent)”?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Hive will set this folder up as a shared workspace so connected agents can coordinate on it.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(pending.url.path(percentEncoded: false))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let message = session.initializationError {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Cancel") {
                    session.pendingInitialization = nil
                }
                .keyboardShortcut(.cancelAction)
                .disabled(session.isInitializing)

                Button {
                    Task { await session.initializeProject(pending) }
                } label: {
                    if session.isInitializing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Initialize")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(session.isInitializing)
            }
        }
        .padding(24)
        .frame(width: HiveMetrics.sheetWidth)
        .interactiveDismissDisabled(session.isInitializing)
    }
}

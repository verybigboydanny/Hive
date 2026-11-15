import SwiftUI

/// "main · 2 uncommitted changes", from the backend's git summary.
struct GitSummaryLabel: View {
    let git: GitSummary

    var body: some View {
        Label {
            if let dirty = git.dirtyFiles, dirty > 0 {
                Text("\(git.branch ?? "detached HEAD") · ^[\(dirty) uncommitted change](inflect: true)")
            } else {
                Text("\(git.branch ?? "detached HEAD") · no uncommitted changes")
            }
        } icon: {
            Image(systemName: "arrow.triangle.branch")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

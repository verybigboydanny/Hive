import SwiftUI

struct BackendHowItWorksView: View {
    var body: some View {
        DisclosureGroup("How Hive runs the backend") {
            VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                Text("The app starts a small local API from the Python code bundled inside it. The API listens only on this Mac and requires a token that is created at each launch and kept in memory.")
                Text("Claude and other agents don't use this API. They talk to a separate MCP server, which you set up on the Connect Claude tab, and both work on the same project files and database.")
                Text("Project data lives in a `.hive` folder inside each project. Hive never opens that database from the app itself.")
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, HiveMetrics.spacing)
        }
    }
}

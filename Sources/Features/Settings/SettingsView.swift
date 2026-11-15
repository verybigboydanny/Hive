import SwiftUI

/// Hive's settings. Almost everything here is read-only because the backend's HTTP API has no write endpoints
/// for it; each page says so where it applies.
struct SettingsView: View {
    @State private var model: SettingsModel

    init(dataSource: any HiveDataSource) {
        _model = State(initialValue: SettingsModel(dataSource: dataSource))
    }

    var body: some View {
        TabView {
            Tab("Apps & MCP", systemImage: "square.grid.2x2") {
                ConnectClaudeView(model: model)
            }
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettingsView()
            }
            Tab("Rules", systemImage: "list.bullet.clipboard") {
                RulesSettingsView(model: model)
            }
            Tab("Permissions", systemImage: "lock.shield") {
                PermissionsSettingsView()
            }
            Tab("Backend", systemImage: "server.rack") {
                BackendSettingsView(model: model)
            }
        }
        .scenePadding()
        .frame(width: HiveMetrics.settingsWidth, height: HiveMetrics.settingsHeight)
        // .hiveTheme() owns color-scheme selection (it handles dark accents + Color Mode together).
        // Do NOT add a bare .preferredColorScheme() above it: that would override the accent's forced scheme.
        .hiveTheme()
        .background { HiveAmbientBackground() }
        .task {
            await model.load()
        }
    }
}

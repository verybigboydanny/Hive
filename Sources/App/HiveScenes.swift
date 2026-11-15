import SwiftUI

/// Hive's scenes, with no entry point of their own.
///
/// Wire this into the project's EXISTING `@main` App type:
///
///     @main
///     struct <ExistingApp>: App {
///         var body: some Scene { HiveScenes() }
///     }
///
/// (or place `HiveScenes()` alongside any scenes the existing app already declares).
struct HiveScenes: Scene {
    @State private var recents = RecentProjects()
    private let dataSource: any HiveDataSource

    init(dataSource: any HiveDataSource) {
        self.dataSource = dataSource
    }

    var body: some Scene {
        WindowGroup {
            RootView(dataSource: dataSource, recents: recents)
        }
        .defaultSize(width: HiveMetrics.defaultWindowWidth, height: HiveMetrics.defaultWindowHeight)
        .commands {
            SidebarCommands()
            ProjectCommands()
        }

        Settings {
            SettingsView(dataSource: dataSource)
        }
    }
}

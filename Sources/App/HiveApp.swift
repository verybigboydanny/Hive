import SwiftUI

@main
struct HiveApp: App {
    @NSApplicationDelegateAdaptor(HiveAppDelegate.self) private var appDelegate

    var body: some Scene {
        HiveScenes(dataSource: appDelegate.dataSource)
    }
}

@MainActor
final class HiveAppDelegate: NSObject, NSApplicationDelegate {
    private let liveDataSource = LiveHiveDataSource()
    private let mockDataSource = MockHiveDataSource()
    private let useMock = ProcessInfo.processInfo.arguments.contains("--hive-mock")
    private var isStopping = false

    var dataSource: any HiveDataSource {
        useMock ? mockDataSource : liveDataSource
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !useMock, !isStopping else { return .terminateNow }
        isStopping = true
        Task {
            await liveDataSource.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

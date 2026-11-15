import Foundation

/// Shared layout constants. Window and pane sizes live here so every screen stays consistent.
enum HiveMetrics {
    // Windows
    static let defaultWindowWidth: Double = 1120
    static let defaultWindowHeight: Double = 740
    static let minWindowWidth: Double = 860
    static let minWindowHeight: Double = 560
    static let settingsWidth: Double = 780
    static let settingsHeight: Double = 640

    // Sidebar, inspectors and split panes
    static let sidebarMinWidth: Double = 180
    static let sidebarIdealWidth: Double = 210
    static let sidebarMaxWidth: Double = 260
    static let inspectorMinWidth: Double = 280
    static let inspectorIdealWidth: Double = 340
    static let inspectorMaxWidth: Double = 460
    static let treeMinWidth: Double = 220
    static let treeIdealWidth: Double = 300
    static let treeMaxWidth: Double = 460
    static let listPaneMinWidth: Double = 280
    static let listPaneIdealWidth: Double = 360

    // Spacing and shape
    static let spacingTight: Double = 4
    static let spacing: Double = 8
    static let spacingLoose: Double = 16
    static let cardPadding: Double = 10
    static let cardRadius: Double = 8
    static let pillHorizontal: Double = 8
    static let pillVertical: Double = 2

    // Components
    static let statusDotSize: Double = 8
    static let recentsPaneWidth: Double = 320
    static let sheetWidth: Double = 420
    static let formSheetWidth: Double = 520
    static let sheetHeight: Double = 440
    static let taskProgressWidth: Double = 120
    static let treeIndent: Double = 14
    static let treeChevronWidth: Double = 14
    static let lineNumberWidth: Double = 44
    static let boardColumnWidth: Double = 270
    static let composerMinHeightLines = 3
    static let welcomeLogoSize: Double = 72
    static let sheetLogoSize: Double = 44
    static let stepBadgeSize: Double = 26
    static let settingsLogoSize: Double = 40
}

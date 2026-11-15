import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @State private var session: ProjectSession
    @State private var showsStartup: Bool
    @AppStorage("hive.appearance") private var appearanceRawValue = HiveAppearance.system.rawValue
    @AppStorage(HiveSettingsKey.accent) private var accentRawValue = HiveAccent.honey.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(dataSource: any HiveDataSource, recents: RecentProjects) {
        _session = State(initialValue: ProjectSession(dataSource: dataSource, recents: recents))
        // Only READ here. SwiftUI may run this initializer more than once before it installs the view, and only
        // the installed copy's State survives, so flipping a flag in init made a discarded copy "use up" the
        // startup animation. The flag is set in onAppear, which runs once for the view that is actually shown.
        _showsStartup = State(initialValue: HiveStartup.shouldPlay)
    }

    /// Dark themes force the dark color scheme; every other theme follows the Color Mode setting.
    private var colorScheme: ColorScheme? {
        HiveAccent.resolve(accentRawValue).forcedColorScheme
            ?? HiveAppearance(rawValue: appearanceRawValue)?.colorScheme
    }

    var body: some View {
        Group {
            if session.project == nil {
                WelcomeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                WorkspaceView()
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.45),
            value: session.project == nil
        )
        .environment(session)
        .focusedSceneValue(\.projectSession, session)
        .preferredColorScheme(colorScheme)
        .frame(minWidth: HiveMetrics.minWindowWidth, minHeight: HiveMetrics.minWindowHeight)
        .overlay {
            if showsStartup {
                HiveStartupView { showsStartup = false }
            }
        }
        // Applied after the overlay so the startup animation receives the selected theme too.
        .hiveTheme()
        .onAppear {
            // The animation plays once per launch, not once per window.
            HiveStartup.hasPlayed = true
        }
        .fileImporter(isPresented: $session.isShowingImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Task { await session.openFolder(url) }
            case .failure(let error):
                session.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $session.pendingInitialization, onDismiss: { session.initializationSheetDismissed() }) { pending in
            InitializeProjectSheet(pending: pending)
                .environment(session)
        }
        .alert("Something Went Wrong", isPresented: showsError) {
            Button("OK") {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var showsError: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )
    }
}

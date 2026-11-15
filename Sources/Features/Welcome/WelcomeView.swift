import SwiftUI

struct WelcomeView: View {
    @Environment(ProjectSession.self) private var session
    @Environment(\.hiveAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingGuide = false
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            intro
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            RecentProjectsList()
                .frame(width: HiveMetrics.recentsPaneWidth)
        }
        .background { HiveAmbientBackground() }
        .sheet(isPresented: $isShowingGuide) {
            HowToUseHiveView()
                .frame(minWidth: 620, minHeight: 620)
        }
        .overlay {
            if session.isOpening {
                ProgressView("Opening…")
                    .padding(20)
                    .hiveGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), tint: accent.color.opacity(0.12))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(HiveMotion.resolved(HiveMotion.spring, reduceMotion: reduceMotion), value: session.isOpening)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return false }
            Task { await session.openFolder(url) }
            return true
        } isTargeted: { targeted in
            withAnimation(HiveMotion.resolved(HiveMotion.spring, reduceMotion: reduceMotion)) {
                isDropTargeted = targeted
            }
        }
    }

    private var intro: some View {
        VStack(spacing: 16) {
            HiveLogo(size: HiveMetrics.welcomeLogoSize)
                .hiveFloat()
                .hiveAppear(delay: 0.05)

            VStack(spacing: 4) {
                Text("Hive")
                    .font(.largeTitle.bold())
                Text("A shared workspace where your AI agents coordinate.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .hiveAppear(delay: 0.12)

            VStack(spacing: 12) {
                Button("Open Project Folder…") {
                    session.isShowingImporter = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.isOpening)

                Button("How to use Hive", systemImage: "book.closed") {
                    isShowingGuide = true
                }
                .buttonStyle(.link)
            }
            .hiveAppear(delay: 0.2)

            Text("Choose a folder, or drop one here. If it isn't a Hive project yet, you can initialize it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .hiveAppear(delay: 0.28)
        }
        .padding(36)
        .hiveGlass(
            in: RoundedRectangle(cornerRadius: 30, style: .continuous),
            tint: accent.color.opacity(isDropTargeted ? 0.28 : 0.10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(accent.color, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .opacity(isDropTargeted ? 1 : 0)
        }
        .scaleEffect(isDropTargeted && !reduceMotion ? 1.02 : 1)
        .padding(40)
    }
}

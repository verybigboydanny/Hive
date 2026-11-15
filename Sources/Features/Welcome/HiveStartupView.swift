import SwiftUI

@MainActor
enum HiveStartup {
    static var hasPlayed = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: HiveSettingsKey.startup) as? Bool ?? true
    }

    static var shouldPlay: Bool {
        isEnabled && !hasPlayed
    }
}

struct HiveStartupView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hiveAccent) private var accent
    @State private var drawn = Array(repeating: false, count: HiveMarkGeometry.cellCount)
    @State private var isFilled = false
    @State private var showsWordmark = false
    @State private var isGlowing = false
    @State private var isLeaving = false
    @State private var didFinish = false
    @State private var sweep: CGFloat = -0.8

    private let markSize: CGFloat = 132

    var body: some View {
        ZStack {
            backdrop
            HiveAmbientBackground(forced: true)
            VStack(spacing: 22) {
                mark
                wordmark
            }
        }
        .ignoresSafeArea()
        .opacity(isLeaving ? 0 : 1)
        .scaleEffect(isLeaving ? 1.06 : 1)
        .blur(radius: isLeaving ? 10 : 0)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await play() }
        .accessibilityHidden(true)
    }

    /// Follows the selected theme: the dark themes' deep base color, frosted glass, or the normal window background.
    @ViewBuilder
    private var backdrop: some View {
        if accent.isFrosted {
            Rectangle().fill(.ultraThinMaterial)
        } else if let base = accent.backdropColor {
            Rectangle().fill(base)
        } else {
            Rectangle().fill(.background)
        }
    }

    private var mark: some View {
        ZStack {
            ForEach(0..<HiveMarkGeometry.cellCount, id: \.self) { index in
                HiveMarkCell(index: index)
                    .fill(accent.gradient)
                    .opacity(isFilled ? 1 : 0)
                    .scaleEffect(isFilled ? 1 : 0.55)
                HiveMarkCell(index: index)
                    .trim(from: 0, to: drawn[index] ? 1 : 0)
                    .stroke(accent.glow, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .opacity(isFilled ? 0 : 1)
            }
        }
        .frame(width: markSize, height: markSize)
        .overlay {
            LinearGradient(
                colors: [.clear, .white.opacity(0.7), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: markSize * 0.45)
            .offset(x: sweep * markSize)
            .frame(width: markSize, height: markSize)
            .mask { HiveMark().fill(.black) }
            .allowsHitTesting(false)
        }
        .shadow(color: accent.color.opacity(isGlowing ? 0.55 : 0.18), radius: isGlowing ? 34 : 14)
    }

    private var wordmark: some View {
        VStack(spacing: 6) {
            Text("Hive")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .tracking(showsWordmark ? 2 : 14)
            Text("Where your agents coordinate")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .opacity(showsWordmark ? 1 : 0)
        .offset(y: showsWordmark ? 0 : 14)
        .blur(radius: showsWordmark ? 0 : 6)
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }

    private func play() async {
        if reduceMotion {
            isFilled = true
            showsWordmark = true
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.2)) { isLeaving = true }
            try? await Task.sleep(for: .milliseconds(220))
            finish()
            return
        }

        for index in 0..<HiveMarkGeometry.cellCount {
            withAnimation(.easeInOut(duration: 0.65)) { drawn[index] = true }
            try? await Task.sleep(for: .milliseconds(60))
        }
        try? await Task.sleep(for: .milliseconds(300))

        withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { isFilled = true }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { isGlowing = true }
        withAnimation(.easeInOut(duration: 0.9).delay(0.2)) { sweep = 0.8 }
        try? await Task.sleep(for: .milliseconds(280))

        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { showsWordmark = true }
        try? await Task.sleep(for: .milliseconds(1100))

        withAnimation(.easeIn(duration: 0.5)) { isLeaving = true }
        try? await Task.sleep(for: .milliseconds(500))
        finish()
    }
}

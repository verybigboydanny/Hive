import SwiftUI

enum HiveAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var detail: String {
        switch self {
        case .system: "Follow your Mac"
        case .light: "Always light"
        case .dark: "Always dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("hive.appearance") private var appearanceRawValue = HiveAppearance.system.rawValue
    @AppStorage(HiveSettingsKey.accent) private var accentRawValue = HiveAccent.honey.rawValue
    @AppStorage(HiveSettingsKey.ambient) private var ambientEnabled = true
    @AppStorage(HiveSettingsKey.startup) private var startupEnabled = true
    @AppStorage(HiveSettingsKey.frostedOpacity) private var frostedOpacity: Double = 0.28
    @Environment(\.hiveAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPreviewingStartup = false
    /// Bumped only for the card that has just been chosen, so only its icon bounces (not the one deselected).
    @State private var bounceTokens: [HiveAppearance: Int] = [:]

    private var appearance: HiveAppearance {
        HiveAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var selectedAccent: HiveAccent {
        HiveAccent.resolve(accentRawValue)
    }

    var body: some View {
        SettingsPage(
            title: "Appearance",
            subtitle: "Choose how Hive looks and moves across its windows."
        ) {
            panel {
                sectionLabel("COLOR MODE")
                HStack(spacing: HiveMetrics.spacing) {
                    ForEach(HiveAppearance.allCases) { option in
                        appearanceCard(option)
                    }
                }
                if selectedAccent.isDarkTheme {
                    Label("\(selectedAccent.title) is a dark theme, so Hive stays dark whatever you choose here.", systemImage: "moon.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .hiveAppear(delay: 0.04)

            panel {
                sectionLabel("ACCENT THEME")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(HiveAccent.allCases) { option in
                        accentSwatch(option)
                    }
                }
                Text("Obsidian, Nebula, Crimson, Forest, Abyss and Frosted are dark themes. Frosted makes the window translucent so your desktop shows through.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .hiveAppear(delay: 0.1)

            if selectedAccent.isFrosted {
                panel {
                    sectionLabel("FROSTED TRANSLUCENCY")
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Background Darkness")
                                .font(.headline)
                            Spacer()
                            Text("\(Int((frostedOpacity * 100).rounded()))%")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $frostedOpacity, in: 0.05...0.75, step: 0.01)
                        Text("Fine-tune how dark and translucent the frosted glass window appears over your desktop.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .hiveAppear(delay: 0.13)
            }

            panel {
                sectionLabel("EFFECTS")
                effectToggle(
                    title: "Ambient glow",
                    detail: "A slow, soft gradient drifting behind every screen.",
                    isOn: $ambientEnabled
                )
                Divider()
                effectToggle(
                    title: "Startup animation",
                    detail: "Play the honeycomb intro when Hive launches.",
                    isOn: $startupEnabled
                )
                Button("Preview Startup Animation", systemImage: "play.fill") {
                    isPreviewingStartup = true
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .hiveAppear(delay: 0.16)

            HStack(spacing: 14) {
                HiveLogo(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Made for the Hive")
                        .font(.headline)
                    Text("Honeycomb geometry, liquid glass, and an accent that follows your taste.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(HiveMetrics.spacingLoose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hiveGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), tint: accent.isFrosted ? nil : accent.color.opacity(0.08))
            .hiveAppear(delay: 0.22)
        }
        .sheet(isPresented: $isPreviewingStartup) {
            HiveStartupView { isPreviewingStartup = false }
                .frame(width: 560, height: 400)
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacing + 4) {
            content()
        }
        .padding(HiveMetrics.spacingLoose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hiveGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }

    private func effectToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn.animation(.smooth(duration: 0.35))) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private func accentSwatch(_ option: HiveAccent) -> some View {
        let isSelected = selectedAccent == option

        return Button {
            withAnimation(HiveMotion.resolved(HiveMotion.bouncy, reduceMotion: reduceMotion)) {
                accentRawValue = option.rawValue
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(option.gradient)
                        .frame(width: 36, height: 36)
                        .shadow(
                            color: option.color.opacity(isSelected ? 0.55 : 0.2),
                            radius: isSelected ? 10 : 4,
                            y: 2
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(option.color, lineWidth: 2)
                        .padding(-5)
                        .scaleEffect(isSelected ? 1 : 0.8)
                        .opacity(isSelected ? 1 : 0)
                }
                Text(option.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .hiveGlass(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                tint: isSelected ? option.color.opacity(0.18) : nil,
                interactive: true
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.hivePress)
        .hiveHover(scale: 1.04)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func appearanceCard(_ option: HiveAppearance) -> some View {
        let isSelected = appearance == option

        return Button {
            if !isSelected { bounceTokens[option, default: 0] += 1 }
            withAnimation(HiveMotion.resolved(HiveMotion.spring, reduceMotion: reduceMotion)) {
                appearanceRawValue = option.rawValue
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: option.symbol)
                        .font(.title3)
                        .foregroundStyle(isSelected ? accent.color : Color.secondary)
                        .symbolEffect(.bounce, options: .nonRepeating, value: bounceTokens[option, default: 0])
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accent.color)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.headline)
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .padding(12)
            .hiveGlass(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                tint: isSelected ? accent.color.opacity(0.16) : nil,
                interactive: true
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? accent.color.opacity(0.6) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.hivePress)
        .hiveHover(scale: 1.02)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

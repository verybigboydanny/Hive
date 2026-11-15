import SwiftUI
import AppKit

enum HiveSettingsKey {
    static let accent = "hive.accent"
    static let ambient = "hive.ambient"
    static let startup = "hive.startup"
    static let appearance = "hive.appearance"
    static let frostedOpacity = "hive.frosted.opacity"
}

enum HiveAccent: String, CaseIterable, Identifiable, Sendable {
    // Light/system-friendly accents first, then the dark themes, then the translucent ones.
    case honey, ember, rose, orchid, midnight, ocean, lagoon, mint, graphite
    case obsidian, nebula, crimson, forest, abyss
    case frosted, frostedDark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .honey: "Honey"
        case .ember: "Ember"
        case .rose: "Rose"
        case .orchid: "Orchid"
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .lagoon: "Lagoon"
        case .mint: "Mint"
        case .graphite: "Graphite"
        case .obsidian: "Obsidian"
        case .nebula: "Nebula"
        case .crimson: "Crimson"
        case .forest: "Forest"
        case .abyss: "Abyss"
        case .frosted: "Frosted"
        case .frostedDark: "Frosted Dark"
        }
    }

    var color: Color {
        switch self {
        case .honey: Color(red: 0.95, green: 0.65, blue: 0.12)
        case .ember: Color(red: 0.96, green: 0.40, blue: 0.22)
        case .rose: Color(red: 0.93, green: 0.33, blue: 0.51)
        case .orchid: Color(red: 0.67, green: 0.40, blue: 0.93)
        case .midnight: Color(red: 0.36, green: 0.42, blue: 0.96)
        case .ocean: Color(red: 0.12, green: 0.55, blue: 0.96)
        case .lagoon: Color(red: 0.10, green: 0.73, blue: 0.74)
        case .mint: Color(red: 0.20, green: 0.78, blue: 0.47)
        case .graphite: Color(red: 0.55, green: 0.58, blue: 0.64)
        case .obsidian: Color(red: 0.78, green: 0.80, blue: 0.88)
        case .nebula: Color(red: 0.62, green: 0.45, blue: 0.98)
        case .crimson: Color(red: 0.93, green: 0.26, blue: 0.30)
        case .forest: Color(red: 0.30, green: 0.78, blue: 0.50)
        case .abyss: Color(red: 0.20, green: 0.62, blue: 0.98)
        case .frosted: Color(red: 0.30, green: 0.58, blue: 0.98)
        case .frostedDark: Color(red: 0.55, green: 0.76, blue: 1.00)
        }
    }

    var glow: Color {
        switch self {
        case .honey: Color(red: 1.00, green: 0.82, blue: 0.30)
        case .ember: Color(red: 1.00, green: 0.65, blue: 0.25)
        case .rose: Color(red: 0.99, green: 0.55, blue: 0.40)
        case .orchid: Color(red: 0.45, green: 0.45, blue: 0.98)
        case .midnight: Color(red: 0.62, green: 0.40, blue: 0.95)
        case .ocean: Color(red: 0.20, green: 0.82, blue: 0.90)
        case .lagoon: Color(red: 0.30, green: 0.88, blue: 0.60)
        case .mint: Color(red: 0.75, green: 0.90, blue: 0.30)
        case .graphite: Color(red: 0.80, green: 0.82, blue: 0.88)
        case .obsidian: Color(red: 0.52, green: 0.58, blue: 0.78)
        case .nebula: Color(red: 0.92, green: 0.40, blue: 0.85)
        case .crimson: Color(red: 1.00, green: 0.52, blue: 0.36)
        case .forest: Color(red: 0.66, green: 0.90, blue: 0.40)
        case .abyss: Color(red: 0.25, green: 0.86, blue: 0.95)
        case .frosted: Color(red: 0.55, green: 0.85, blue: 1.00)
        case .frostedDark: Color(red: 0.88, green: 0.94, blue: 1.00)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, glow], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Dark themes always use the dark color scheme, whatever the Color Mode setting says.
    var isDarkTheme: Bool {
        switch self {
        case .obsidian, .nebula, .crimson, .forest, .abyss, .frosted, .frostedDark: true
        default: false
        }
    }

    /// The window shows what is behind it, blurred, like frosted glass.
    var isFrosted: Bool { self == .frosted || self == .frostedDark }

    var forcedColorScheme: ColorScheme? { isDarkTheme ? .dark : nil }

    /// The deep, tinted base color painted behind every screen of a dark theme.
    var backdropColor: Color? {
        switch self {
        case .obsidian: Color(red: 0.045, green: 0.047, blue: 0.056)
        case .nebula: Color(red: 0.060, green: 0.040, blue: 0.120)
        case .crimson: Color(red: 0.105, green: 0.030, blue: 0.040)
        case .forest: Color(red: 0.030, green: 0.080, blue: 0.060)
        case .abyss: Color(red: 0.020, green: 0.048, blue: 0.108)
        default: nil
        }
    }

    static func resolve(_ rawValue: String) -> HiveAccent {
        HiveAccent(rawValue: rawValue) ?? .honey
    }
}

private struct HiveAccentKey: EnvironmentKey {
    static let defaultValue: HiveAccent = .honey
}

extension EnvironmentValues {
    var hiveAccent: HiveAccent {
        get { self[HiveAccentKey.self] }
        set { self[HiveAccentKey.self] = newValue }
    }
}

/// Applies the selected theme to a window's content: accent, color scheme (dark themes force dark) and backdrop.
/// Used by every scene, including Settings, so they all show the same theme.
///
/// Anything that reads `hiveAccent` (the ambient glow, the startup animation) has to sit INSIDE this modifier.
/// A `.background { HiveAmbientBackground() }` added after `.hiveTheme()` is outside it and falls back to the
/// default honey accent.
private struct HiveThemeModifier: ViewModifier {
    @AppStorage(HiveSettingsKey.accent) private var accentRawValue = HiveAccent.honey.rawValue
    @AppStorage(HiveSettingsKey.appearance) private var appearanceRawValue = HiveAppearance.system.rawValue

    func body(content: Content) -> some View {
        let accent = HiveAccent.resolve(accentRawValue)
        content
            .environment(\.hiveAccent, accent)
            .tint(accent.color)
            .preferredColorScheme(accent.forcedColorScheme ?? HiveAppearance(rawValue: appearanceRawValue)?.colorScheme)
            .background { HiveThemeBackdrop(accent: accent) }
            .animation(.smooth(duration: 0.45), value: accentRawValue)
    }
}

extension View {
    func hiveTheme() -> some View {
        modifier(HiveThemeModifier())
    }
}

// MARK: - Backdrop (dark base color / frosted translucency)

/// Paints the theme's base layer and, for the frosted themes, makes the window itself translucent.
private struct HiveThemeBackdrop: View {
    let accent: HiveAccent
    @AppStorage(HiveSettingsKey.frostedOpacity) private var frostedOpacity = 0.28

    var body: some View {
        ZStack {
            if accent.isFrosted {
                // Frosted window: dark HUD blur + dark tint with user-tunable opacity.
                // No blue overlay tint is added, keeping it crisp, transparent, and frosted.
                HiveVisualEffectBackground(material: .hudWindow)
                Color.black.opacity(frostedOpacity)
            } else if let base = accent.backdropColor {
                base
            }
            HiveWindowConfigurator(isTranslucent: accent.isFrosted)
                .frame(width: 0, height: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A blurred view of whatever is behind the window.
private struct HiveVisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Makes the hosting window transparent (frosted) or restores the normal opaque window (every other theme).
private struct HiveWindowConfigurator: NSViewRepresentable {
    let isTranslucent: Bool

    func makeNSView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.isTranslucent = isTranslucent
        return view
    }

    func updateNSView(_ view: ConfiguratorView, context: Context) {
        view.isTranslucent = isTranslucent
        view.apply()
    }

    final class ConfiguratorView: NSView {
        var isTranslucent = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            window.isOpaque = !isTranslucent
            window.backgroundColor = isTranslucent ? .clear : .windowBackgroundColor
        }
    }
}

// MARK: - System panels (tables, grouped forms, section headers)

/// In dark mode the system paints table stripes, grouped-form cards and section bars in an opaque grey. On the dark
/// themes that grey sits on the tinted backdrop like a hole. These modifiers swap it for a see-through wash so the
/// theme shows through. In light mode they change nothing.
private struct HiveTableStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(colorScheme == .dark ? .hidden : .automatic)
            .alternatingRowBackgrounds(colorScheme == .dark ? .disabled : .automatic)
    }
}

private struct HiveGroupedBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.scrollContentBackground(colorScheme == .dark ? .hidden : .automatic)
    }
}

private struct HivePanelRowsModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let wash: Color? = colorScheme == .dark ? HivePanel.wash : nil
        content.listRowBackground(wash)
    }
}

enum HivePanel {
    /// The see-through fill used instead of the system's opaque grey: a faint lift of the backdrop.
    static let wash = Color.white.opacity(0.07)
}

extension View {
    /// For a `Table`: no opaque container or alternating stripes in dark mode.
    func hiveTableStyle() -> some View {
        modifier(HiveTableStyleModifier())
    }

    /// For a grouped `Form` or `List`: hides the opaque container in dark mode. Pair it with `hivePanelRows()` on the
    /// form's sections.
    func hiveGroupedBackground() -> some View {
        modifier(HiveGroupedBackgroundModifier())
    }

    /// For a `Section` (or row) of a grouped form: a see-through card instead of opaque grey in dark mode.
    func hivePanelRows() -> some View {
        modifier(HivePanelRowsModifier())
    }
}

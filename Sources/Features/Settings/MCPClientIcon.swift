import AppKit
import SwiftUI

@MainActor
struct MCPClientIcon: View {
    let bundleIdentifier: String?
    let fallbackSymbol: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hiveAccent) private var accent
    @State private var appIcon: NSImage?

    var body: some View {
        Group {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(accent.color.opacity(0.12))
                    .transition(.opacity)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .animation(
            reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.78),
            value: appIcon != nil
        )
        .task(id: bundleIdentifier) {
            loadApplicationIcon()
        }
        .accessibilityHidden(true)
    }

    init(target: MCPClientTarget) {
        bundleIdentifier = target.iconBundleIdentifier
        switch target.id {
        case let id where id.hasPrefix("claude."):
            fallbackSymbol = "bubble.left.and.bubble.right.fill"
        case "antigravity", "antigravity.cli":
            fallbackSymbol = "sparkles"
        case "gemini.cli":
            fallbackSymbol = "terminal.fill"
        case "cursor":
            fallbackSymbol = "cursorarrow"
        case "windsurf":
            fallbackSymbol = "wind"
        case "copilot", "vscode.profile":
            fallbackSymbol = "chevron.left.forwardslash.chevron.right"
        case "codex":
            fallbackSymbol = "sparkle"
        case "zed":
            fallbackSymbol = "command"
        default:
            fallbackSymbol = "app"
        }
    }

    init(bundleIdentifier: String?, fallbackSymbol: String) {
        self.bundleIdentifier = bundleIdentifier
        self.fallbackSymbol = fallbackSymbol
    }

    private func loadApplicationIcon() {
        guard let bundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            appIcon = nil
            return
        }
        appIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}

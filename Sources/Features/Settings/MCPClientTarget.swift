import Foundation

enum MCPConfigSchema: String, Hashable, Sendable {
    case mcpServers
    case servers
    case contextServers
    case codexTOML
}

struct MCPClientTarget: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let configURL: URL
    let schema: MCPConfigSchema
    let iconBundleIdentifier: String?
    let family: String
    let isProfile: Bool
    let isDetected: Bool
    /// Other config files that must receive the same entry (older app versions that still read a legacy location).
    var mirrorConfigURLs: [URL] = []

    /// The same target pointing at a different config file.
    func retargeted(to url: URL) -> MCPClientTarget {
        MCPClientTarget(
            id: id, name: name, detail: detail, configURL: url, schema: schema,
            iconBundleIdentifier: iconBundleIdentifier, family: family, isProfile: isProfile, isDetected: isDetected
        )
    }

    static func discover(home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) -> [MCPClientTarget] {
        let fm = FileManager.default
        func url(_ path: String) -> URL { home.appending(path: path) }
        func appExists(_ names: [String]) -> Bool {
            let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true), home.appending(path: "Applications", directoryHint: .isDirectory)]
            return roots.contains { root in
                guard let items = try? fm.contentsOfDirectory(atPath: root.path) else { return false }
                return items.contains { item in names.contains(where: { item.localizedCaseInsensitiveContains($0) }) }
            }
        }

        let claudePath = url("Library/Application Support/Claude/claude_desktop_config.json")
        var targets = [MCPClientTarget(
            id: "claude.default", name: "Claude Desktop", detail: "Default profile", configURL: claudePath,
            schema: .mcpServers, iconBundleIdentifier: "com.anthropic.claudefordesktop", family: "Claude", isProfile: true,
            isDetected: fm.fileExists(atPath: claudePath.path) || appExists(["Claude.app"])
        )]

        // Claude Profiles launches each Desktop profile with --user-data-dir=<~/.claude-instances/<slug>>.
        let profilesRoot = home.appending(path: ".claude-instances", directoryHint: .isDirectory)
        if let profiles = try? fm.contentsOfDirectory(at: profilesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for profile in profiles where (try? profile.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let config = profile.appending(path: "claude_desktop_config.json")
                guard fm.fileExists(atPath: config.path) else { continue }
                targets.append(MCPClientTarget(
                    id: "claude.profile.\(profile.lastPathComponent)",
                    name: "Claude Desktop · \(profile.lastPathComponent)",
                    detail: "Claude Profiles instance", configURL: config, schema: .mcpServers,
                    iconBundleIdentifier: "com.anthropic.claudefordesktop", family: "Claude", isProfile: true, isDetected: true
                ))
            }
        }

        let definitions: [(String, String, String, String, MCPConfigSchema, String?, [String])] = [
            // Antigravity 2.0, the IDE and the CLI share ONE global config (~/.gemini/config/mcp_config.json, per
            // antigravity.google/docs/mcp). Older IDE builds read ~/.gemini/antigravity/mcp_config.json; when that
            // folder exists it is written too (see `mirrorConfigURLs` below).
            ("antigravity", "Google Antigravity", "Shared by Antigravity IDE, CLI and 2.0", ".gemini/config/mcp_config.json", .mcpServers, "com.google.antigravity", ["Antigravity"]),
            ("gemini.cli", "Gemini CLI", "User settings", ".gemini/settings.json", .mcpServers, nil, ["Gemini"]),
            ("cursor", "Cursor", "Global MCP config", ".cursor/mcp.json", .mcpServers, "com.todesktop.230313mzl4w4u92", ["Cursor"]),
            ("windsurf", "Windsurf", "Global MCP config", ".codeium/windsurf/mcp_config.json", .mcpServers, "com.exafunction.windsurf", ["Windsurf"]),
            ("copilot", "GitHub Copilot", "Global MCP config", ".copilot/mcp-config.json", .mcpServers, "com.microsoft.VSCode", ["Visual Studio Code", "VS Code"]),
            ("vscode.profile", "VS Code profile", "User MCP config", "Library/Application Support/Code/User/mcp.json", .servers, "com.microsoft.VSCode", ["Visual Studio Code", "VS Code"]),
            ("codex", "Codex", "Shared Codex and ChatGPT desktop config", ".codex/config.toml", .codexTOML, "com.openai.codex", ["Codex"]),
            ("zed", "Zed", "User settings", "Library/Application Support/Zed/settings.json", .contextServers, "dev.zed.Zed", ["Zed"])
        ]

        for (id, name, detail, path, schema, iconBundleIdentifier, appNames) in definitions {
            let config = url(path)
            let parentExists = fm.fileExists(atPath: config.deletingLastPathComponent().path)
            var mirrors: [URL] = []
            var legacyExists = false
            if id == "antigravity" {
                let legacyFolder = url(".gemini/antigravity")
                legacyExists = fm.fileExists(atPath: legacyFolder.path)
                if legacyExists { mirrors.append(legacyFolder.appending(path: "mcp_config.json")) }
            }
            let detected = fm.fileExists(atPath: config.path) || parentExists || legacyExists || appExists(appNames)
            var target = MCPClientTarget(
                id: id, name: name, detail: detail, configURL: config, schema: schema,
                iconBundleIdentifier: iconBundleIdentifier, family: "Other apps", isProfile: false, isDetected: detected
            )
            target.mirrorConfigURLs = mirrors
            targets.append(target)
        }
        return targets
    }
}

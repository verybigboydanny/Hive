import SwiftUI
import UniformTypeIdentifiers

/// Installs Hive's local MCP server in several AI clients while keeping Claude profiles easy to manage.
struct ConnectClaudeView: View {
    let model: SettingsModel

    @AppStorage("hive.mcp.serverName") private var serverName = "hive"
    @AppStorage("hive.mcp.bootstrapPython") private var bootstrapPython = ""
    @AppStorage("hive.mcp.extraClaudeConfigs") private var extraClaudeConfigs = ""
    @AppStorage("hive.mcp.selectedTargetIDs") private var storedSelection = ""
    @State private var showingConfigImporter = false
    @State private var showingSetupConfirmation = false
    @State private var showingChatGPTInfo = false
    @State private var workflow = MCPConnectionsWorkflow()

    private var setup: MCPSetup {
        var value = MCPSetup(
            bootstrapPython: bootstrapPython.isEmpty ? Self.detectedPython : bootstrapPython,
            backendSourcePath: Self.backendSourcePath,
            workspacePath: model.workspace?.root ?? ""
        )
        value.projectID = model.workspace?.projectID ?? ""
        value.serverName = serverName
        return value
    }

    private var allTargets: [MCPClientTarget] {
        let discovered = MCPClientTarget.discover()
        let knownPaths = Set(discovered.map { $0.configURL.standardizedFileURL.path })
        let custom = extraClaudeConfigs
            .split(separator: "\n")
            .map(String.init)
            .filter { !knownPaths.contains(URL(fileURLWithPath: $0).standardizedFileURL.path) }
            .map { path in
                MCPClientTarget(
                    id: "claude.custom.\(path)", name: "Claude Desktop · \(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent)",
                    detail: "Additional profile", configURL: URL(fileURLWithPath: path),
                    schema: .mcpServers, iconBundleIdentifier: "com.anthropic.claudefordesktop",
                    family: "Claude", isProfile: true, isDetected: true
                )
            }
        return discovered + custom
    }

    private var selectedIDs: Set<String> {
        Set(storedSelection.split(separator: "\n").map(String.init))
    }

    private var selectedTargets: [MCPClientTarget] {
        allTargets.filter { selectedIDs.contains($0.id) }
    }

    private var claudeTargets: [MCPClientTarget] { allTargets.filter(\.isProfile) }
    private var otherTargets: [MCPClientTarget] { allTargets.filter { !$0.isProfile } }

    var body: some View {
        SettingsPage(
            title: "Connect Hive to your AI apps",
            subtitle: "Choose where Hive should appear. Hive prepares one local server and adds it to each selected app. It works for every project."
        ) {
            brandHeader
            ConnectProjectStatus(model: model, usesCustomFolder: false)

            VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                HStack {
                    Label("Claude Desktop profiles", systemImage: "bubble.left.and.bubble.right")
                        .font(.headline)
                    Spacer()
                    Button(allClaudeProfilesSelected ? "Deselect all" : "Select all") {
                        setSelection(claudeTargets, selected: !allClaudeProfilesSelected)
                    }
                    .buttonStyle(.link)
                    .disabled(claudeTargets.isEmpty)
                }
                Text("Found \(claudeTargets.count) profile\(claudeTargets.count == 1 ? "" : "s"). Claude Profiles instances are detected from their separate config folders.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(claudeTargets) { target in
                    targetRow(target)
                }

                Button("Add another Claude profile config…", systemImage: "plus") {
                    showingConfigImporter = true
                }
                .buttonStyle(.link)
            }
            .padding(HiveMetrics.spacingLoose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                Label("Other MCP apps", systemImage: "square.grid.2x2")
                    .font(.headline)
                Text("Hive can add its local connection to these apps too. Select the ones you use.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(otherTargets) { target in
                    targetRow(target)
                }
            }
            .padding(HiveMetrics.spacingLoose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))

            chatGPTCard

            if let warning = setup.backendPathWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showingSetupConfirmation = true
            } label: {
                Label(workflow.isRunning ? "Adding Hive…" : "Add Hive to \(selectedTargets.count) selected app\(selectedTargets.count == 1 ? "" : "s")", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)
            .disabled(workflow.isRunning || selectedTargets.isEmpty)

            Label("The connection works for every project. Choose the project for each agent in Set Up Agent.", systemImage: "person.badge.plus")
                .font(.callout)
                .foregroundStyle(.secondary)

            if workflow.isRunning {
                ProgressView(workflow.status ?? "Preparing connections…")
                    .controlSize(.small)
            }
            if let error = workflow.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let result = workflow.result {
                VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                    Label(workflow.status ?? "Setup complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    ForEach(result.configuredTargets, id: \.self) { name in
                        Text("• \(name)").font(.caption)
                    }
                    if !result.backupURLs.isEmpty {
                        Text("Existing configs backed up: \(result.backupURLs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
            }

            DisclosureGroup("Manual setup and copy prompts") {
                VStack(alignment: .leading, spacing: HiveMetrics.spacing) {
                    Text("All selected apps receive the same project-agnostic server command. Agents name their project with the id from Set Up Agent. Existing config entries are preserved.")
                        .foregroundStyle(.secondary)
                    CodeBlock(text: ([setup.venvPython] + setup.serverArguments).map(MCPSetup.shell).joined(separator: " "))
                    ConnectPromptsView(
                        setup: setup,
                        agentName: .constant("Claude"),
                        agentRole: .constant(""),
                        taskID: .constant(""),
                        handoffRecipient: .constant("")
                    )
                }
                .padding(.top, HiveMetrics.spacing)
            }
        }
        .onAppear {
            if selectedIDs.isEmpty {
                setSelection(allTargets.filter(\.isDetected), selected: true)
            }
        }
        .fileImporter(
            isPresented: $showingConfigImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            let current = Set(extraClaudeConfigs.split(separator: "\n").map(String.init))
            let additions = urls.map { $0.standardizedFileURL.path }.filter {
                URL(fileURLWithPath: $0).lastPathComponent == "claude_desktop_config.json" && !current.contains($0)
            }
            guard !additions.isEmpty else { return }
            extraClaudeConfigs = (current.union(additions)).sorted().joined(separator: "\n")
            let fresh = allTargets.filter { additions.contains($0.configURL.standardizedFileURL.path) }
            setSelection(fresh, selected: true)
        }
        .confirmationDialog(
            "Add Hive to the selected apps?",
            isPresented: $showingSetupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Add to \(selectedTargets.count) apps") {
                Task { await workflow.run(setup: setup, targets: selectedTargets) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hive will prepare its local runtime and update \(selectedTargets.count) config file\(selectedTargets.count == 1 ? "" : "s"). Existing entries will be preserved and existing files backed up. Claude profiles are configured separately. Restart selected apps to load Hive.\n\n\(selectedTargets.map(\.name).joined(separator: ", "))")
        }
        .sheet(isPresented: $showingChatGPTInfo) {
            ChatGPTMCPInfoView()
        }
    }

    private var allClaudeProfilesSelected: Bool {
        !claudeTargets.isEmpty && claudeTargets.allSatisfy { selectedIDs.contains($0.id) }
    }

    private var brandHeader: some View {
        HStack(spacing: 16) {
            Image("HiveBrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Hive honeycomb icon")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("HIVE MCP")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.31))
                    Text("LOCAL")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                Text("One Hive. Every agent.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Connect your MCP apps to this project's shared workspace.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.20, green: 0.14, blue: 0.08), Color(red: 0.08, green: 0.07, blue: 0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.62, blue: 0.13).opacity(0.15))
                        .frame(width: 130, height: 130)
                        .blur(radius: 35)
                        .offset(x: 25, y: -45)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
        }
    }

    private var chatGPTCard: some View {
        HStack(alignment: .top, spacing: HiveMetrics.spacing) {
            MCPClientIcon(bundleIdentifier: "com.openai.codex", fallbackSymbol: "sparkle")
            VStack(alignment: .leading, spacing: HiveMetrics.spacingTight) {
                Text("ChatGPT")
                    .font(.headline)
                Text("ChatGPT needs an HTTPS MCP endpoint or Secure MCP Tunnel. Hive currently connects through local stdio, so this needs a different transport.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("See ChatGPT connection options…") { showingChatGPTInfo = true }
                    .buttonStyle(.link)
            }
        }
        .padding(HiveMetrics.spacingLoose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func targetRow(_ target: MCPClientTarget) -> some View {
        Toggle(isOn: selectionBinding(for: target)) {
            HStack(spacing: 10) {
                MCPClientIcon(target: target)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: HiveMetrics.spacingTight) {
                        Text(target.name)
                            .font(.body.weight(.medium))
                        if target.isDetected {
                            Text("FOUND")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                    }
                    Text("\(target.detail) · \(displayPath(target.configURL))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(workflow.isRunning)
    }

    private func selectionBinding(for target: MCPClientTarget) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(target.id) },
            set: { setSelection([target], selected: $0) }
        )
    }

    private func setSelection(_ targets: [MCPClientTarget], selected: Bool) {
        var updated = selectedIDs
        for target in targets {
            if selected { updated.insert(target.id) } else { updated.remove(target.id) }
        }
        storedSelection = updated.sorted().joined(separator: "\n")
    }

    private func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private static var backendSourcePath: String {
        Bundle.main.resourceURL?.appending(path: "hive-backend/src").path(percentEncoded: false) ?? "hive-backend/src"
    }

    private static var detectedPython: String {
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "python3"
    }
}

private struct ChatGPTMCPInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: HiveMetrics.spacingLoose) {
            HStack {
                HiveLogo(size: 48)
                Text("Connect Hive to ChatGPT")
                    .font(.title2.bold())
            }
            Text("ChatGPT custom MCP apps connect to an HTTPS MCP server. A local server can be reached through Secure MCP Tunnel. Hive's current connection runs as a local stdio process, so it cannot be added to ChatGPT directly yet.")
                .fixedSize(horizontal: false, vertical: true)
            Text("To support ChatGPT, Hive needs a Streamable HTTP MCP transport and a tunnel or hosted endpoint. Once that is available, add it in ChatGPT under Apps → Create, then provide the server URL or select the tunnel.")
                .fixedSize(horizontal: false, vertical: true)
            Link("Open ChatGPT's MCP setup guide", destination: URL(string: "https://developers.openai.com/api/docs/guides/custom-mcp-server")!)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
    }
}

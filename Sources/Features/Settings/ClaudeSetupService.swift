import Foundation
import Observation

struct MCPConnectionsResult: Sendable {
    let configuredTargets: [String]
    let backupURLs: [URL]
}

enum MCPConnectionsError: LocalizedError, Sendable {
    case pythonTooOld(String)
    case commandFailed(String, Int32, String)
    case invalidConfig(String, String)

    var errorDescription: String? {
        switch self {
        case .pythonTooOld(let version):
            return "Hive needs Python 3.11 or later. The detected version is \(version). Install a newer Python and try again."
        case .commandFailed(let command, let code, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(command) stopped with error code \(code)."
                : "\(command) stopped with error code \(code): \(detail)"
        case .invalidConfig(let path, let reason):
            return "Hive couldn't safely update \(path): \(reason). That file was left unchanged."
        }
    }
}

/// Prepares one local MCP runtime and merges its server entry into selected client configs.
enum MCPConnectionsService {
    private static let minimumPython = (3, 11)

    static func configure(
        using setup: MCPSetup,
        targets: [MCPClientTarget],
        progress: @MainActor @Sendable (String) -> Void
    ) async throws -> MCPConnectionsResult {
        await progress("Checking Python…")
        let versionOutput = try await run(
            executable: "/usr/bin/env",
            arguments: [setup.bootstrapPython, "-c", "import sys; print('.'.join(map(str, sys.version_info[:3])))"]
        )
        guard let version = parseVersion(versionOutput),
              version.major > minimumPython.0 || (version.major == minimumPython.0 && version.minor >= minimumPython.1)
        else {
            throw MCPConnectionsError.pythonTooOld(versionOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        await progress("Preparing Hive's shared MCP runtime…")
        _ = try await run(executable: "/usr/bin/env", arguments: [setup.bootstrapPython, "-m", "venv", setup.venvPath])
        _ = try await run(
            executable: setup.venvPython,
            arguments: ["-m", "pip", "install", "--disable-pip-version-check", MCPSetup.sdkRequirement]
        )

        var backups: [URL] = []
        for (index, target) in targets.enumerated() {
            await progress("Adding Hive to \(target.name) (\(index + 1) of \(targets.count))…")
            // Some apps keep an older config location as well (see `MCPClientTarget.mirrorConfigURLs`).
            for destination in [target.configURL] + target.mirrorConfigURLs {
                if let backup = try writeEntry(for: target.retargeted(to: destination), setup: setup) {
                    backups.append(backup)
                }
            }
        }
        return MCPConnectionsResult(configuredTargets: targets.map(\.name), backupURLs: backups)
    }

    private static func parseVersion(_ value: String) -> (major: Int, minor: Int)? {
        let pieces = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard pieces.count >= 2, let major = Int(pieces[0]), let minor = Int(pieces[1]) else { return nil }
        return (major, minor)
    }

    private static func run(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let logURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("hive-setup-\(UUID().uuidString).log")
                do {
                    _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
                    let log = try FileHandle(forWritingTo: logURL)
                    defer {
                        try? log.close()
                        try? FileManager.default.removeItem(at: logURL)
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.standardOutput = log
                    process.standardError = log
                    try process.run()
                    process.waitUntilExit()
                    try log.close()

                    let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                    guard process.terminationStatus == 0 else {
                        throw MCPConnectionsError.commandFailed(
                            URL(fileURLWithPath: executable).lastPathComponent,
                            process.terminationStatus,
                            String(output.suffix(1_200))
                        )
                    }
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func writeEntry(for target: MCPClientTarget, setup: MCPSetup) throws -> URL? {
        if target.schema == .codexTOML {
            return try writeCodexEntry(for: target, setup: setup)
        }

        let fileManager = FileManager.default
        let hadExistingConfig = fileManager.fileExists(atPath: target.configURL.path)
        var root: [String: Any] = [:]
        if hadExistingConfig {
            do {
                let data = try Data(contentsOf: target.configURL)
                // An empty file is what a freshly created config looks like; treat it as `{}`.
                if !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
                    guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw MCPConnectionsError.invalidConfig(target.configURL.path, "the top level must be a JSON object")
                    }
                    root = parsed
                }
            } catch let error as MCPConnectionsError {
                throw error
            } catch {
                throw MCPConnectionsError.invalidConfig(target.configURL.path, "the file is not valid JSON (\(error.localizedDescription))")
            }
        }

        let key = target.schema.rawValue
        var servers: [String: Any] = [:]
        if let existing = root[key] {
            guard let dictionary = existing as? [String: Any] else {
                throw MCPConnectionsError.invalidConfig(target.configURL.path, "`\(key)` must be an object")
            }
            servers = dictionary
        }
        servers[setup.effectiveServerName] = serverEntry(for: target, setup: setup)
        root[key] = servers

        do {
            try fileManager.createDirectory(at: target.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let backup = try makeBackup(of: target.configURL, existed: hadExistingConfig)
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: target.configURL, options: .atomic)
            try verifyEntry(at: target.configURL, key: key, serverName: setup.effectiveServerName)
            return backup
        } catch let error as MCPConnectionsError {
            throw error
        } catch {
            throw MCPConnectionsError.invalidConfig(target.configURL.path, "could not write the file (\(error.localizedDescription))")
        }
    }

    /// Reads the file back so a write that silently went elsewhere (for example into a sandbox container) is reported.
    private static func verifyEntry(at url: URL, key: String, serverName: String) throws {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root[key] as? [String: Any],
              servers[serverName] != nil
        else {
            throw MCPConnectionsError.invalidConfig(url.path, "the entry was not found after writing")
        }
    }

    private static func serverEntry(for target: MCPClientTarget, setup: MCPSetup) -> [String: Any] {
        var entry: [String: Any]
        if target.id == "antigravity" {
            // Antigravity's handling of `env` for stdio servers is not reliable (reported by users), and a server
            // without PYTHONPATH cannot import `hive`. Put the variable on the command line instead.
            entry = ["command": setup.environmentFreeCommand, "args": setup.environmentFreeArguments]
        } else {
            entry = [
                "command": setup.venvPython,
                "args": setup.serverArguments,
                "env": setup.serverEnvironment
            ]
        }
        if target.id == "copilot" || target.schema == .servers {
            entry["type"] = "stdio"
        }
        return entry
    }

    private static func writeCodexEntry(for target: MCPClientTarget, setup: MCPSetup) throws -> URL? {
        let fileManager = FileManager.default
        let existed = fileManager.fileExists(atPath: target.configURL.path)
        let original: String
        do {
            original = existed ? try String(contentsOf: target.configURL, encoding: .utf8) : ""
        } catch {
            throw MCPConnectionsError.invalidConfig(target.configURL.path, "the file could not be read (\(error.localizedDescription))")
        }

        let header = "[mcp_servers.\(setup.effectiveServerName)]"
        let lines = original.components(separatedBy: .newlines)
        var kept: [String] = []
        var skipping = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                skipping = trimmed == header || trimmed == "[[mcp_servers.\(setup.effectiveServerName)]]"
            }
            if !skipping { kept.append(line) }
        }
        while kept.last == "" { kept.removeLast() }

        let args = setup.serverArguments.map(tomlString).joined(separator: ", ")
        let entry = [
            header,
            "command = \(tomlString(setup.venvPython))",
            "args = [\(args)]",
            "env = { PYTHONPATH = \(tomlString(setup.backendSourcePath)) }"
        ].joined(separator: "\n")
        let merged = (kept.isEmpty ? entry : kept.joined(separator: "\n") + "\n\n" + entry) + "\n"

        do {
            try fileManager.createDirectory(at: target.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let backup = try makeBackup(of: target.configURL, existed: existed)
            try merged.write(to: target.configURL, atomically: true, encoding: .utf8)
            return backup
        } catch let error as MCPConnectionsError {
            throw error
        } catch {
            throw MCPConnectionsError.invalidConfig(target.configURL.path, "could not write the file (\(error.localizedDescription))")
        }
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private static func makeBackup(of url: URL, existed: Bool) throws -> URL? {
        guard existed else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.appendingPathExtension("hive-backup-\(stamp)")
        try FileManager.default.copyItem(at: url, to: backup)
        return backup
    }
}

@MainActor @Observable
final class MCPConnectionsWorkflow {
    private(set) var status: String?
    private(set) var result: MCPConnectionsResult?
    private(set) var error: String?
    private(set) var isRunning = false

    func run(setup: MCPSetup, targets: [MCPClientTarget]) async {
        guard !isRunning, !targets.isEmpty else { return }
        isRunning = true
        status = "Starting…"
        result = nil
        error = nil
        defer { isRunning = false }

        do {
            result = try await MCPConnectionsService.configure(using: setup, targets: targets) { [weak self] message in
                self?.status = message
            }
            status = "Hive was added to \(targets.count) app configuration\(targets.count == 1 ? "" : "s"). Restart those apps to load it."
        } catch {
            self.error = error.localizedDescription
            status = nil
        }
    }
}

import Foundation

/// Everything the "Connect Claude" page shows: setup commands, config, and the prompts to paste into Claude.
///
/// Facts used here come from the backend, not from guesses:
/// - The MCP server is `python -m hive mcp` (backend `cli.py`). It is project-agnostic: it is NOT told a project
///   folder. Each agent names its project with `agent_register(project_id: ...)`, using the id from Set Up Agent,
///   so one entry in a client's global config serves every project and nothing stale can be baked into it.
/// - It needs the backend source on `PYTHONPATH` (the app bundles it) and the official MCP SDK.
/// - The SDK must be the 1.x line: the backend adapter fails to start with SDK 2.x
///   (`'Server' object has no attribute 'list_tools'`), which is why the requirement is `mcp>=1.2,<2`
///   and not the `mcp>=1.2` the backend's own error message suggests.
/// - Every tool and parameter named in the prompts exists in backend-contract.md; `MCPSetupTests` checks that.
struct MCPSetup: Equatable, Sendable {
    static let sdkRequirement = "mcp>=1.2,<2"
    static let minimumPython = "3.11"
    static let placeholderWorkspace = "/path/to/your/project"

    /// Python used once to create the virtual environment (`python3`, or an absolute path to Python 3.11+).
    var bootstrapPython: String = "python3"
    /// The bundled backend source folder (`…/Hive.app/Contents/Resources/hive-backend/src`).
    var backendSourcePath: String
    /// The open project's folder. Used only for the `doctor` check; it is NOT part of any client config.
    var workspacePath: String
    /// The open project's stable id (`prj_…`), from the backend. Empty until a project is open.
    var projectID: String = ""
    var serverName: String = "hive"
    var agentName: String = "Claude"
    var agentRole: String = ""
    var taskID: String = ""
    var handoffRecipient: String = ""
    var homeDirectory: String = NSHomeDirectory()

    // MARK: Derived values

    var effectiveWorkspace: String { workspacePath.isEmpty ? Self.placeholderWorkspace : workspacePath }
    var usesPlaceholderWorkspace: Bool { workspacePath.isEmpty }
    var effectiveServerName: String { serverName.trimmingCharacters(in: .whitespaces).isEmpty ? "hive" : serverName.trimmingCharacters(in: .whitespaces) }

    var venvPath: String { homeDirectory + "/.hive-mcp-venv" }
    var venvPython: String { venvPath + "/bin/python" }
    var venvPip: String { venvPath + "/bin/pip" }

    static let claudeDesktopConfigPath = "~/Library/Application Support/Claude/claude_desktop_config.json"

    /// Xcode's build folder changes when the project is cleaned, so a path inside it is fragile.
    var backendPathWarning: String? {
        if backendSourcePath.contains("/DerivedData/") {
            return "This copy of Hive is inside Xcode's build folder, which moves or disappears when you clean the project. Copy the folder “hive-backend” to a permanent place and use that path for PYTHONPATH."
        }
        if backendSourcePath.contains("/AppTranslocation/") {
            return "macOS is running this copy of Hive from a temporary location. Move Hive.app to Applications and reopen it, then use the path shown here."
        }
        return nil
    }

    // MARK: Setup commands (Terminal)

    var checkPythonCommand: String { "\(Self.shell(bootstrapPython)) --version" }
    var createVenvCommand: String { "\(Self.shell(bootstrapPython)) -m venv \(Self.shell(venvPath))" }
    var installSDKCommand: String { "\(Self.shell(venvPip)) install \(Self.shell(Self.sdkRequirement))" }
    var verifyCommand: String {
        "PYTHONPATH=\(Self.shell(backendSourcePath)) \(Self.shell(venvPython)) -m hive doctor --workspace \(Self.shell(effectiveWorkspace))"
    }

    /// The four setup commands as one pasteable block.
    var setupScript: String {
        [createVenvCommand, installSDKCommand, verifyCommand].joined(separator: "\n")
    }

    // MARK: Claude configuration

    /// Project-agnostic on purpose (see the type's documentation).
    var serverArguments: [String] { ["-m", "hive", "mcp"] }
    var serverEnvironment: [String: String] { ["PYTHONPATH": backendSourcePath] }

    /// For clients that do not reliably pass `env` to the server process (reported for Google Antigravity): the
    /// variable is given on the command line through `env`, so the server starts regardless.
    var environmentFreeCommand: String { "/usr/bin/env" }
    var environmentFreeArguments: [String] { ["PYTHONPATH=\(backendSourcePath)", venvPython] + serverArguments }

    /// Claude Desktop's `claude_desktop_config.json` content (a complete file for a first-time setup).
    var claudeDesktopConfig: String {
        let args = serverArguments.map(Self.jsonString).joined(separator: ", ")
        return """
        {
          "mcpServers": {
            \(Self.jsonString(effectiveServerName)): {
              "command": \(Self.jsonString(venvPython)),
              "args": [\(args)],
              "env": {
                "PYTHONPATH": \(Self.jsonString(backendSourcePath))
              }
            }
          }
        }
        """
    }

    /// Just the server entry, for adding to a config file that already has `mcpServers`.
    var claudeDesktopEntry: String {
        let args = serverArguments.map(Self.jsonString).joined(separator: ", ")
        return """
        \(Self.jsonString(effectiveServerName)): {
          "command": \(Self.jsonString(venvPython)),
          "args": [\(args)],
          "env": {
            "PYTHONPATH": \(Self.jsonString(backendSourcePath))
          }
        }
        """
    }

    /// Claude Code: all options go before the server name; `--` separates the server command.
    var claudeCodeCommand: String {
        let env = Self.shell("PYTHONPATH=" + backendSourcePath)
        let command = ([venvPython] + serverArguments).map(Self.shell).joined(separator: " ")
        return "claude mcp add --transport stdio --env \(env) \(Self.shell(effectiveServerName)) -- \(command)"
    }

    // MARK: Prompts to paste into Claude

    private var trimmedName: String { agentName.trimmingCharacters(in: .whitespaces).isEmpty ? "Claude" : agentName.trimmingCharacters(in: .whitespaces) }
    private var trimmedRole: String { agentRole.trimmingCharacters(in: .whitespaces) }
    private var trimmedTask: String { taskID.trimmingCharacters(in: .whitespaces) }
    private var trimmedRecipient: String { handoffRecipient.trimmingCharacters(in: .whitespaces) }

    private var trimmedProjectID: String { projectID.trimmingCharacters(in: .whitespaces) }

    /// The project line shared by the prompts: the exact id when known, otherwise an instruction NOT to guess.
    private var projectClause: String {
        trimmedProjectID.isEmpty
            ? "I have not given you a Hive project id. Ask me for it before you register; do not guess a project from an earlier registration or your working directory."
            : "The Hive project id is \(trimmedProjectID). Pass it as `project_id`; Hive refuses any other project."
    }

    private var projectArgument: String { trimmedProjectID.isEmpty ? "" : "`project_id` \"\(trimmedProjectID)\", " }

    /// Short manual prompt. The Set Up Agent screen generates the complete, per-agent instruction; prefer that.
    var onboardPrompt: String {
        let role = trimmedRole.isEmpty ? "" : ", `role` \"\(trimmedRole)\""
        return """
        You are joining a Hive workspace through the "\(effectiveServerName)" MCP server. Hive lets several AI agents work on one project without overwriting each other. \(projectClause)

        1. Call `agent_register` with \(projectArgument)`name` "\(trimmedName)" and `client` "claude"\(role). Add `model` (your model identifier, if you know it) and `capabilities` (a short list of what you can do).
        2. Show me `agent.id` and `resume_token` from the result, exactly as returned, and remind me to store them somewhere safe. The token is a secret and is shown only once. With both values you can reconnect later under the same identity.
        3. Call `agent_get_context`, then summarise the project rules, your tasks, the tasks you could claim, unread messages and pending handoffs.
        4. Do not claim a task or change any file until I tell you which task to work on.
        """
    }

    var reconnectPrompt: String {
        """
        Reconnect to Hive under your existing identity. \(projectClause)

        1. Call `agent_register` with \(projectArgument)`name` "\(trimmedName)", `agent_id` "PASTE_YOUR_SAVED_AGENT_ID" and `resume_token` "PASTE_YOUR_SAVED_RESUME_TOKEN". They must be given together, and the project id must be the project that issued them.
        2. Call `agent_get_context` and continue from `last_checkpoint` if there is one.
        """
    }

    var contextPrompt: String {
        """
        Refresh your picture of the project in Hive.

        1. Call `agent_get_context` with `activity_limit` 20.
        2. Call `message_inbox`. Act on anything addressed to you, then call `message_mark_read` for the messages you have handled.
        3. If `pending_handoffs` is not empty, describe each one to me and ask whether to accept it with `handoff_accept`. Do not accept one without my approval.
        4. Report back: your current tasks, the tasks you could claim, anything blocked, and what you recommend doing next.
        """
    }

    var startTaskPrompt: String {
        let selection = trimmedTask.isEmpty
            ? "Work on a Hive task. Call `task_list` with `claimable_only` true, recommend the highest-priority task, and wait for my go-ahead before claiming it."
            : "Work on the Hive task \(trimmedTask)."
        let lookup = trimmedTask.isEmpty
            ? "1. Once I confirm the task, call `task_list` with its `task_id` and read its description and `blocked_by`."
            : "1. Call `task_list` with `task_id` \"\(trimmedTask)\" and read its description and `blocked_by`."
        return """
        \(selection)

        \(lookup) If it is blocked or `claimable` is false, stop and tell me why.
        2. Call `task_claim` with that `task_id` and `lease_minutes` 30. If it fails with TASK_ALREADY_CLAIMED or DEPENDENCY_UNMET, stop and tell me.
        3. Before changing a file, call `read_file`. When you save it, call `write_file` with the `expected_sha256` from your latest read. If you get CONFLICT, re-read and merge; never overwrite blindly. Use `create_file` for new files.
        4. After each meaningful step, call `task_update` with `status` "in_progress" and a short `progress_note`. This also renews your claim. Call `save_checkpoint` at milestones.
        5. When you are done, call `task_complete` with a `summary` of what you delivered.
        6. If you cannot continue, call `task_update` with `status` "blocked" and explain what you need.
        """
    }

    var handoffPrompt: String {
        let task = trimmedTask.isEmpty ? "the task you currently own" : "task \(trimmedTask)"
        let recipient = trimmedRecipient.isEmpty
            ? "Leave `to` out so any agent can accept it."
            : "Set `to` to \"\(trimmedRecipient)\"."
        let taskArgument = trimmedTask.isEmpty ? "`task_id` (the task you own)" : "`task_id` \"\(trimmedTask)\""
        return """
        Hand \(task) over to another agent in Hive.

        1. Call `save_checkpoint` with a `summary` of where you are, the `task_id`, `files_modified` and `next_action`.
        2. Call `handoff_create` with a one-line `summary`, \(taskArgument), `completed_work`, `remaining_work`, `files_modified`, `next_action`, and `context` (anything the next agent must know). \(recipient)
        3. Do not complete or release the task yourself. Ownership moves when the recipient calls `handoff_accept`.
        4. Tell me the handoff id and who can accept it, then call `agent_update_status` with `status` "idle".
        """
    }

    /// A prompt that makes Claude add a project rule (the app itself cannot: the HTTP API has no endpoint for rules).
    static let addRulePrompt = """
        Add a project rule to Hive that every agent will see.

        1. Call `memory_read` with `key` "rules/TOPIC" (choose a short topic) to check whether the rule already exists.
        2. If it does not exist, call `memory_update` with `key` "rules/TOPIC", `category` "rules", and `value` set to the rule, written as one clear instruction.
        3. If it exists, call `memory_update` with the same `key` and pass the entry's current version as `expected_version`, so you do not overwrite someone else's change.
        4. Tell me the key you used and the final wording.
        """

    /// Every prompt, for verification.
    var allPrompts: [String] { [onboardPrompt, reconnectPrompt, contextPrompt, startTaskPrompt, handoffPrompt, Self.addRulePrompt] }

    // MARK: Quoting

    /// A JSON string literal (quotes included), without escaping slashes.
    static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8), text.count >= 4
        else { return "\"\(value)\"" }
        return String(text.dropFirst().dropLast())
    }

    /// Quotes a value for a POSIX shell only when it needs it.
    static func shell(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

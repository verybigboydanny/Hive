import Foundation

/// The AI client an agent will run in. Only a label stored on the agent (`agent_register.client`).
enum AgentClient: String, CaseIterable, Identifiable, Sendable {
    case claude, antigravity, codex, cursor, windsurf, copilot, gemini, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .antigravity: "Google Antigravity"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .windsurf: "Windsurf"
        case .copilot: "GitHub Copilot"
        case .gemini: "Gemini CLI"
        case .other: "Other"
        }
    }
}

/// What the user enters in Set Up Agent. The project is never part of it: it is the open project.
struct AgentSetupRequest: Hashable, Sendable {
    var name: String
    var role: String
    var capabilities: [String]
    var client: AgentClient
}

/// The generated onboarding instruction (`POST /v1/onboarding/prompt`).
struct AgentOnboarding: Hashable, Sendable {
    var prompt: String
    var projectID: String
    var projectName: String
    var warnings: [String]
}

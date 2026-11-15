# Set Up Agent

1. Open a project in Hive and connect Hive to your AI app once (see [mcp-setup.md](mcp-setup.md)).
2. Open **Set Up Agent** in the sidebar (⌘8). The project is the one open in the window; it is shown, not typed.
3. Enter a name, role, optional capabilities and the AI client. Press **Set Up Agent**.
4. Copy the instruction into a new chat in that app.

The agent then: registers with `agent_register` (passing the exact `project_id`), shows you `agent.id` and the secret
`resume_token`, calls `agent_get_context`, summarises rules, assigned and claimable tasks, unread messages and pending
handoffs, and **waits** before claiming tasks or touching files.

## What guarantees the right project

* The instruction carries the project id; the backend verifies it (`PROJECT_MISMATCH` / `PROJECT_UNKNOWN` /
  `PROJECT_REQUIRED`) and the instruction tells the agent to stop and report, not to retry elsewhere.
* The app asks the backend for the instruction with the selected project's id; if the backend has a different project
  open, it refuses instead of generating one.
* Reconnecting needs `project_id`, `agent_id` and `resume_token` together; a token from one project fails in another.

## Notes

* Treat the resume token like a password. Hive stores only its SHA-256.
* Agent names are labels; the id is the identity. Hive warns when a name repeats.
* The `hive_onboard` / `hive_resume` MCP prompts accept a `project_id` argument.
* Backend: `POST /v1/onboarding/prompt` (see [backend-contract.md](backend-contract.md)).

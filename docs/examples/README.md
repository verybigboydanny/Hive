# Example configuration

Placeholders only (`YOU`, `/Applications/Hive.app`). Hive's **Settings → Apps & MCP** page writes the real values for
you and backs up any file it changes; use these only for manual setup.

None of them names a project folder. The server is project-agnostic: each agent names its project with the id from
**Set Up Agent**. Antigravity's file is `~/.gemini/config/mcp_config.json` (shared by its IDE, CLI and 2.0); its entry
passes `PYTHONPATH` on the command line because `env` handling there has been reported as unreliable.

# Hive

Hive is a native macOS workspace for coordinating AI agents on a shared project: a SwiftUI app, a local Python
backend with an MCP server, and one-click setup for compatible AI apps. Hive does not run or proxy any model.

## Requirements

* macOS 15 or later, Xcode 16 or later (the project uses Swift 6)
* Python 3.11 or later (the backend uses only the standard library; the MCP server needs `mcp>=1.2,<2`)

## Build and run

1. Open `Hive.xcodeproj`, select the **Hive** scheme and run on My Mac. Or, unsigned, from Terminal:

   ```sh
   xcodebuild -project Hive.xcodeproj -scheme Hive -configuration Debug \
     -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
   ```

2. Open or initialise a project folder. `--hive-mock` as a launch argument shows the UI with fabricated data.
3. **Settings → Apps & MCP**: add Hive to your AI apps once (works for every project), restart them.
4. **Set Up Agent**: name an agent, copy the generated instruction into that app. See
   [docs/agent-onboarding.md](docs/agent-onboarding.md).

ChatGPT needs an HTTPS MCP endpoint; the local stdio server cannot be added there directly.

## Backend without the app

```sh
python3 -m venv .venv && .venv/bin/pip install -e '.[mcp]'
.venv/bin/hive init /path/to/project --name "My project"   # prints the project id
.venv/bin/hive projects                                     # registered projects
.venv/bin/hive doctor --workspace /path/to/project
.venv/bin/hive mcp                                          # project-agnostic MCP server on stdio
```

Environment: `HIVE_HOME` (default `~/.hive`) holds `projects.json`, the id → folder registry (ids, names and folder
paths only, mode 0600). Project data lives in each project's `.hive/` folder, which Hive keeps out of git status.

## Layout

| Path | Contents |
|---|---|
| `Sources/` | SwiftUI app (features, design system, models, services) |
| `Resources/hive-backend/` | Python backend, bundled into the app |
| `scripts/` | Real MCP SDK verification script |
| `docs/` | Architecture, backend contract, MCP setup, onboarding, example configs |
| `Branding/hive-mark.svg` | Source of the app mark (the icon set is in `Sources/Assets.xcassets`) |
| `hive-website/` | Static product site (see its README) |

## License

No license file is included in this repository. Add one before publishing.

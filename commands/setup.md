---
description: Check that Cursor Agent CLI (cursor-agent) is installed and signed in, and create the plugin-owned config dir whose deny rules every delegated run uses
argument-hint: ""
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

Run these steps in order and finish with one consolidated status block. Never print token, API key or credential values.

`FORWARD` below means `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cursor-forward.sh"` — the same script the `cursor-rescue` subagent runs, so setup checks exactly what delegation will hit.

Step 1 — Probe

```bash
FORWARD preflight
```

Read the exit code and act, then rerun Step 1 after any fix (at most three times in total):

- **127** (`cursor-agent not found`) → use `AskUserQuestion` exactly once: `Install Cursor Agent CLI (Recommended)` / `Skip for now`. Install commands: Windows PowerShell `irm 'https://cursor.com/install?win32=true' | iex`; macOS/Linux/WSL `curl https://cursor.com/install -fsS | bash`. If the user skips, jump to the report. On Windows the script calls the bundled `node.exe` + `index.js` under `%LOCALAPPDATA%\cursor-agent\versions\` (newest first) instead of the `cursor-agent.cmd` shim, which passes arguments through `cmd.exe` and cuts a multi-line prompt at its first line break.
- **78** (`missing deny rules`) → Step 2.
- **70** (`not signed in`) → tell the user to sign in once with `cursor-agent login` (browser flow; on Windows run it from PowerShell or cmd, where the shim is fine for this), or to export a Cursor API key as `CURSOR_API_KEY`. Then rerun `/cursor:setup`.
- **0** → note the `CLI <version>, plan <tier>` line and continue with Step 3.

Step 2 — Plugin-owned config dir (the safety net)

Every delegated run sets `CURSOR_CONFIG_DIR=$HOME/.cursor-rescue`, so `cursor-agent` reads `cli-config.json` from there instead of `~/.cursor/cli-config.json`. Two effects: the deny rules apply to delegated runs only (interactive Cursor sessions keep the user's settings), and a `--model` passed to a delegated run is remembered only there — `cursor-agent` saves the last `--model` as the default of the config dir it runs with (verified: a named model left in the user-level config breaks every later run on the Free plan).

Read `$HOME/.cursor-rescue/cli-config.json` (it may not exist) and compare `permissions.deny` with `${CLAUDE_PLUGIN_ROOT}/docs/cli-config.json`:

- Missing → create the directory and copy the template as is. No question needed: the directory belongs to this plugin.
- Present but missing rules → add only the missing `permissions.deny` entries, keep every other key and rule untouched, write valid JSON.

Then rerun Step 1.

Step 3 — Version

Floor: **2026.09.26** (verified on 2026.09.26 and 2026.09.28). Older → suggest `cursor-agent update`. The CLI also updates itself into a new `versions/` directory; the script always picks the newest one.

Step 4 — Claude Code plugins inside Cursor (Windows)

`cursor-agent` imports the user's Claude Code setup on its own: the plugins in `~/.claude/plugins/installed_plugins.json` with their hooks, skills and agents, `~/.claude/skills`, `~/.claude/agents`, and permission rules from `~/.claude/settings.json`. On Windows it runs imported hook commands through PowerShell, so a hook written for bash fails, and a failing `PreToolUse` hook blocks the tool call (verified with claude-mem: every file write and read was rejected with `Hook blocked with message: ... syntax error near unexpected token`).

Check whether this machine is exposed:

```bash
python - <<'PY' 2>/dev/null || echo "python not available: look for hooks/*.json under the installPath of each plugin in ~/.claude/plugins/installed_plugins.json"
import json, os, glob
data = json.load(open(os.path.expanduser("~/.claude/plugins/installed_plugins.json"), encoding="utf-8")).get("plugins", {})
for name, entries in data.items():
    for entry in (entries if isinstance(entries, list) else [entries]):
        if glob.glob(os.path.join(entry.get("installPath", ""), "hooks", "*.json")):
            print("plugin with hooks:", name)
PY
```

- Windows and at least one plugin with hooks → write `on` to `$HOME/.cursor-rescue/isolate` and say why in one sentence. Isolated runs set `CURSOR_RESCUE_FAKE_HOME`, and `scripts/cursor-preload.js` (loaded into Cursor's own Node process with `node --require`) then makes `os.homedir()` return `$HOME/.cursor-rescue/home`, so Cursor no longer finds `~/.claude` (nor the user's `~/.cursor` chats and MCP servers). Environment variables are untouched, so the commands the delegate runs keep the real `USERPROFILE`, `HOME` and `APPDATA` — git, SSH, NuGet, npm and the sign-in (`%APPDATA%\Cursor\auth.json`) keep working (verified).
- No plugins with hooks, or not Windows → write `off`. On macOS/Linux hooks run under bash as intended, and the preload needs the Windows `node.exe` bundle anyway.
- On Windows the caller can override per run with `--isolate` / `--no-isolate`.

Step 5 — Verify the deny rules bite (spends one agent request)

Ask once with `AskUserQuestion`: `Run the deny probe (Recommended)` / `Skip`. On the Free plan every agent request counts against the monthly allowance. If run:

```bash
cd "$(mktemp -d)" && git init -q && printf '%s\n' 'Run exactly this shell command and print its output: git push --dry-run origin HEAD. If it is blocked, reply BLOCKED and quote the reason.' | FORWARD run --model auto
```

Expected: a `  x shell: Command blocked by permissions configuration: git push ...` line or a `BLOCKED` answer quoting that reason. Anything else → report that the deny rules are not being applied and stop recommending delegation until fixed.

Step 6 — Models

```bash
FORWARD models
```

Report the plan from Step 1 and how many models are listed. **Free plan: only `auto` runs** — any named model fails with `ActionRequiredError: Named models unavailable Free plans can only use Auto` (verified); the script switches to `auto` on its own. Paid plans can pass any listed slug with `--model <slug>`.

Step 7 — Consolidated report

One short block: launcher and CLI version vs floor, sign-in state and plan, config dir and deny-rule state with the Step 5 result, isolation state and why, models available, and how to delegate (`/cursor:rescue <task>`, `/cursor:rescue --read-only <review task with the diff pasted>`, or let the `cursor-rescue` subagent fire proactively).

---
description: Check that Cursor Agent CLI (cursor-agent) is installed and signed in, and create the plugin-owned config dir whose deny rules every delegated run uses
argument-hint: ""
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

Run these steps in order and finish with one consolidated status block. Never print token, API key or credential values.

Step 1 — Locate the CLI

```bash
CA_ROOT="${LOCALAPPDATA//\\//}/cursor-agent"
VER=$(ls -d "$CA_ROOT"/versions/*/ 2>/dev/null | sort -V | tail -1)
if [ -n "$VER" ] && [ -f "${VER}node.exe" ]; then echo "windows bundle: ${VER}node.exe ${VER}index.js"
elif command -v cursor-agent >/dev/null 2>&1; then echo "on PATH: $(command -v cursor-agent)"
elif [ -x "$HOME/.local/bin/cursor-agent" ]; then echo "found: $HOME/.local/bin/cursor-agent"
else echo "NOT FOUND"; fi
```

- Not found → use `AskUserQuestion` exactly once with two options: `Install Cursor Agent CLI (Recommended)` and `Skip for now`. Install commands: Windows PowerShell `irm 'https://cursor.com/install?win32=true' | iex`; macOS/Linux/WSL `curl https://cursor.com/install -fsS | bash`. Rerun Step 1 afterwards. If the user skips, jump to the report.
- On Windows the subagent calls the bundled `node.exe` with `index.js` directly instead of the `cursor-agent.cmd` shim: a `.cmd` shim passes arguments through `cmd.exe`, which cuts a multi-line prompt at its first line break and re-parses quotes (verified). Nothing to fix here; just report which launcher was found.

In the steps below, `CA` means that launcher: `"${VER}node.exe" "${VER}index.js"` on Windows, otherwise `cursor-agent`.

Step 2 — Version

```bash
CURSOR_CONFIG_DIR="$HOME/.cursor-rescue" <CA> about </dev/null
```

`about` answers locally plus one account lookup — no agent turn, no quota spent. Report `CLI Version` and `Latest`. Floor: **2026.09.26** (verified on 2026.09.26 and 2026.09.28). Older → suggest `cursor-agent update` and continue. The CLI also updates itself into a new `versions/` directory; the subagent always picks the newest one.

Step 3 — Authentication

From the same `about` output:

- `User Email` shows an address → signed in. Report the `Subscription Tier`.
- `User Email  Not logged in` and no `CURSOR_API_KEY` in the environment → tell the user to sign in once: `cursor-agent login` (browser flow; on Windows run it from PowerShell or cmd, where the shim works fine for this). A Cursor API key in `CURSOR_API_KEY` works too. Then rerun `/cursor:setup`.

Step 4 — Plugin-owned config dir (the safety net)

Every delegated run sets `CURSOR_CONFIG_DIR=$HOME/.cursor-rescue`, so `cursor-agent` reads its `cli-config.json` from there instead of `~/.cursor/cli-config.json`. Two effects: the deny rules below apply to delegated runs only (your interactive Cursor sessions keep your own settings), and a `--model` passed to a delegated run is remembered only there (`cursor-agent` persists the last `--model` as the default model of whatever config dir it uses — verified).

Read `$HOME/.cursor-rescue/cli-config.json` (it may not exist yet) and compare `permissions.deny` with `${CLAUDE_PLUGIN_ROOT}/docs/cli-config.json`.

- File missing → create the directory and copy the template there as is. No question needed: the directory belongs to this plugin.
- File present but missing rules → add only the missing `permissions.deny` entries, keep every other key and rule untouched, write valid JSON.

Step 5 — Verify the deny rules bite (spends one agent request)

Ask once with `AskUserQuestion`: `Run the deny probe (Recommended)` / `Skip`. On the Free plan every agent request counts against the monthly allowance. If run:

```bash
cd "$(mktemp -d)" && git init -q && \
CURSOR_CONFIG_DIR="$HOME/.cursor-rescue" MSYS_NO_PATHCONV=1 GIT_TERMINAL_PROMPT=0 timeout 300 <CA> -p "Run exactly this shell command and print its output: git push --dry-run origin HEAD. If it is blocked, reply BLOCKED and quote the reason." --output-format text --trust --workspace "$(pwd -W 2>/dev/null || pwd)" --force --model auto </dev/null
```

Expected: `BLOCKED` with `Command blocked by permissions configuration`. Anything else → report that the deny rules are not being applied and stop recommending delegation until fixed.

Step 6 — Claude Code plugins inside Cursor (Windows)

`cursor-agent` imports the user's Claude Code setup on its own: plugins listed in `~/.claude/plugins/installed_plugins.json` (with their hooks, skills and agents), `~/.claude/skills`, `~/.claude/agents`, and permission rules from `~/.claude/settings.json`. On Windows it runs imported hook commands through PowerShell, so a hook written for bash fails — and a failing `PreToolUse` hook blocks the tool call (verified with the claude-mem plugin: every file write and read was rejected with `Hook blocked with message: ... syntax error near unexpected token`).

Check whether this machine is exposed:

```bash
python - <<'PY' 2>/dev/null || node -e "console.log('python not available; check ~/.claude/plugins/installed_plugins.json by hand')"
import json, os, glob
p = os.path.expanduser("~/.claude/plugins/installed_plugins.json")
data = json.load(open(p, encoding="utf-8")).get("plugins", {})
for name, entries in data.items():
    for e in (entries if isinstance(entries, list) else [entries]):
        path = e.get("installPath", "")
        if glob.glob(os.path.join(path, "hooks", "*.json")):
            print("plugin with hooks:", name)
PY
```

- Windows and at least one plugin with hooks → write the word `on` to `$HOME/.cursor-rescue/isolate` and say why in one sentence. Isolated runs load a three-line preload into Cursor's own Node process that makes `os.homedir()` return `$HOME/.cursor-rescue/home`, so Cursor no longer finds `~/.claude` (nor `~/.cursor` chats and MCP servers). Environment variables are untouched, so the commands the delegate runs keep the real `USERPROFILE`, `HOME` and `APPDATA` — git, SSH, NuGet, npm and the sign-in (`%APPDATA%\Cursor\auth.json`) keep working (verified).
- No plugins with hooks, or not Windows → write `off`. On macOS/Linux the hooks run under bash as intended, and the preload is not used there: the launcher is a shell script the subagent cannot add `--require` to, and the sign-in path derives from the home directory.
- On Windows the caller can override per run with `--isolate` / `--no-isolate`; elsewhere the flags are ignored.

Step 7 — Models

```bash
CURSOR_CONFIG_DIR="$HOME/.cursor-rescue" <CA> models </dev/null
```

Report the tier from Step 3 and how many models are listed. **Free plan: only `auto` runs** — any named model fails with `ActionRequiredError: Named models unavailable Free plans can only use Auto` (verified); the subagent always passes `--model auto` there. Paid plans can pass any listed slug with `--model <slug>`.

Step 8 — Consolidated report

One short block: launcher, CLI version vs floor and latest, sign-in state and tier, config dir and deny-rule state with the Step 5 result, isolation state and why, models available, and how to delegate (`/cursor:rescue <task>`, `/cursor:rescue --read-only <review task>`, or let the `cursor-rescue` subagent fire proactively).

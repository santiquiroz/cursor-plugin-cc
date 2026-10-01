# cursor-plugin-cc

Delegate coding tasks from [Claude Code](https://claude.com/claude-code) to
[Cursor Agent CLI](https://cursor.com/docs/cli/overview) (`cursor-agent`) in
headless mode.

Claude Code stays the orchestrator — it writes the domain logic, defines each
subtask contract, and reviews the diffs. Cursor is **an extra agentic lane on
its own quota**: the delegate reads and edits files and runs commands in your
repo itself, and `--read-only` runs it in Cursor's ask mode for reviews and
diagnoses that must not touch the working tree. On Cursor's **Free plan only
the `auto` model runs**; paid plans can name any model `cursor-agent models`
lists.

Sibling of [copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc),
[antigravity-plugin-cc](https://github.com/santiquiroz/antigravity-plugin-cc),
[ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc) and
[bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc), all
inspired by the structure of [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).
**Not affiliated with Cursor (Anysphere), OpenAI, GitHub, Google or Anthropic.**

> Lea esto en español: [README.es.md](README.es.md)

## Where it sits in a delegation chain

| Tier | Delegate | Good for |
|---|---|---|
| trivial | [ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc) | one-shot text transforms on a small local model |
| medium (local) | [bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc) | bounded agentic tasks on a big local model |
| mechanical | [copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc) | boilerplate, renames, simple specs, cleanup |
| **extra agentic lane** | **cursor-plugin-cc (this)** | bounded tasks when the other lanes are out of quota, read-only second opinions |
| frontier, second lane | [antigravity-plugin-cc](https://github.com/santiquiroz/antigravity-plugin-cc) | Codex fallback, second opinions |
| frontier, primary | Codex / your main reasoning delegate | architecture-adjacent implementation, deep diagnosis |

Only the lanes you install exist; the plugin works alone too.

## Requirements

- Claude Code. The forwarder runs through the Bash tool (Git Bash on Windows).
- [Cursor Agent CLI](https://cursor.com/docs/cli/installation) — verified on
  **2026.09.26** and **2026.09.28** — signed in once with `cursor-agent login` (or a
  `CURSOR_API_KEY`). Windows PowerShell:
  `irm 'https://cursor.com/install?win32=true' | iex` — macOS/Linux/WSL:
  `curl https://cursor.com/install -fsS | bash`.
- A Cursor account. The Free plan works, with two limits: only `auto`, and a
  monthly allowance of agent requests.

## Install

In Claude Code:

```
/plugin marketplace add santiquiroz/cursor-plugin-cc
/plugin install cursor@cursor-plugin-cc
```

Then, once per machine:

```
/cursor:setup
```

Setup locates the CLI, checks version and sign-in, creates the plugin-owned
config dir `~/.cursor-rescue/` with the deny rules every delegated run uses,
optionally verifies they bite (one agent request), decides whether delegated
runs must be isolated from your Claude Code plugins (Windows, see below), and
lists the models your plan can use.

## Usage

```
/cursor:rescue add unit tests for src/utils/money.ts covering rounding and negative amounts (signatures pasted below) ...
/cursor:rescue --background rename UserDto to UserResponse across src/api and update the imports
/cursor:rescue --read-only review src/services/billing.ts for race conditions; report only
```

### Flags and limits

Put the flags first, then the task text.

- `--wait` (default) — foreground. Claude Code blocks on one `cursor-agent`
  call; a run can take up to 9 minutes. Interrupting it rolls nothing back:
  whatever Cursor already edited stays in your working tree.
- `--background` — the subagent runs in the background and its output is
  relayed when the run ends. Use it for anything longer than a minute.
- `--model <slug>` — paid plans only. On the Free plan the subagent switches to
  `auto` and says so in the first line of the output.
- `--read-only` — runs Cursor's ask mode (`--mode ask`): file edits are refused
  and, in testing, shell commands were rejected too, so paste the diff or the
  code into the task instead of asking Cursor to run `git diff`.
- `--isolate` / `--no-isolate` — override the isolation default set by setup
  (Windows only, see below).

Every run is capped at 9 minutes (`timeout -k 10 540`, under the Bash tool
ceiling; `cursor-agent` has no print-timeout of its own). The subagent asks for
`stream-json` and prints a compact progress log — assistant text, one line per
tool call, a line per denial — so a run cut by the cap still shows what
happened; the edits made until then are in your working tree. **Cursor's
`auto` model on the Free plan is slow** — in testing a trivial reply took
20–90 s and a run with eight shell commands did not finish in 9 minutes — so
size tasks small: one spec file, one rename, one review.

**Resuming.** The subagent adds `--continue` when your request clearly
continues prior Cursor work in this repo ("continue", "keep going",
"resume"). Delegated runs keep their own chat history (see isolation below on
Windows), so `--continue` picks up the last delegated run, not your
interactive Cursor sessions.

### Proactive delegation

The `cursor-rescue` agent's description tells Claude Code to use it on its own
when your other delegates are out of quota or busy, or for a read-only second
opinion. That run sends the task text to Cursor's backend and lets the model
edit files in the current repository with tool calls auto-approved (the deny
rules still apply). What stands between that and your working tree is Claude
Code's own permission system: the subagent's only tool is `Bash`, so in the
default permission mode you approve the launch command before it runs, while
under bypass mode it runs unprompted. If you want delegation only on request,
skip the CLAUDE.md snippet and add this line to `~/.claude/CLAUDE.md`:

```
Never launch cursor:cursor-rescue on your own; use it only when I invoke /cursor:rescue explicitly.
```

To make proactive delegation routine instead, paste the block from
[docs/claude-md-snippet.md](docs/claude-md-snippet.md) into your `CLAUDE.md`;
lane split, WIP caps and the fallback chain are in
[docs/delegation-guide.md](docs/delegation-guide.md).

## What the forwarder actually runs

Simplified (Windows bundle shown; on macOS/Linux the launcher is `cursor-agent`):

```bash
export CURSOR_CONFIG_DIR="$HOME/.cursor-rescue"      # plugin-owned cli-config.json with the deny rules
TASK=$(cat <<'EOF_TASK'
<your task, verbatim>

Constraints: work directly in this workspace ... Do not commit, push, switch branches or delete files ...
EOF_TASK
)
MSYS_NO_PATHCONV=1 GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" NO_OPEN_BROWSER=1 \
timeout -k 10 540 "$VER/node.exe" [--require ~/.cursor-rescue/homedir-preload.js] "$VER/index.js" \
  -p "$TASK" --output-format stream-json --trust --workspace "$(pwd -W)" --force --model auto \
  [--mode ask] [--continue] </dev/null 2>&1 | <compact progress filter>
```

## Safety model

Facts about headless `cursor-agent` this plugin is built on (verified on
2026.09.26 and 2026.09.28, Windows 11):

- `-p` without `--force` cannot prompt, so tool calls that need approval are
  rejected. The forwarder passes `--force`, and **`permissions.deny` rules
  still win** under it (`Command blocked by permissions configuration`).
- `CURSOR_CONFIG_DIR` relocates `cli-config.json`. The plugin keeps its own in
  `~/.cursor-rescue/`, so its deny rules apply to delegated runs only, and your
  interactive Cursor sessions keep your own settings. It also contains the
  **model leak**: `cursor-agent` saves the last `--model` as the default model
  of the config dir it ran with — a test run with a named model left the
  user-level config pointing at a model the Free plan cannot use. The sign-in
  lives elsewhere (`%APPDATA%\Cursor\auth.json` on Windows), so it is shared.
- Deny rules match the **first command** of each shell call. In testing, a
  deny on `rm` did not stop `bash -c "rm a.txt"` or
  `powershell -Command "Remove-Item a.txt"` — the file was deleted. The
  plugin's rules therefore also deny the wrapper shells and runners
  (`bash`, `sh`, `zsh`, `powershell`, `pwsh`, `cmd`, `wsl`, `env`, `xargs`,
  `Start-Process`). Interpreters (`node`, `python`, …) are not denied — builds
  and tests need them — so a determined delegate can still delete through a
  script. Treat the list as a guardrail, not a sandbox.

The deny list ([docs/cli-config.json](docs/cli-config.json)):

| Rules | Blocks |
|---|---|
| `Shell(git push)`, `reset`, `clean`, `checkout`, `switch`, `restore`, `stash`, `rebase`, `commit`, `rm`, `worktree`, `config` | shared state, discarding work, history changes |
| `Shell(rm)`, `rmdir`, `del`, `erase`, `rd`, `ri`, `Remove-Item` | deleting files |
| `Shell(bash)`, `sh`, `zsh`, `fish`, `dash`, `powershell`, `pwsh`, `cmd`, `wsl`, `env`, `xargs`, `Start-Process` | wrapper shells that hide the commands above |
| `Shell(sudo)`, `runas` | privilege escalation |
| `Shell(claude)`, `codex`, `copilot`, `agy`, `gemini`, `ollama`, `cursor-agent`, `agent` | recursive delegation to other AI CLIs |
| `Write(**/.git/**)` | editing repository metadata |

What this does **not** cover — know it before delegating:

- Shell commands run as your OS user and can reach any path on disk. The
  delegate edits your live working tree; do not edit the same files while a
  `--background` run is in flight. Commit or stash your own work first.
- Web search and fetch are Cursor tools, not shell commands; `curl`, `npm
  install` and friends are not denied. Do not delegate tasks that process
  untrusted content.
- `cursor-agent` also merges permission rules from `~/.claude/settings.json`
  and `<repo>/.claude/settings.json` into its own (it reads them on start).

### Isolation from your Claude Code setup (Windows)

`cursor-agent` imports your Claude Code configuration on its own: the plugins
in `~/.claude/plugins/installed_plugins.json` with their **hooks**, skills and
agents, `~/.claude/skills`, `~/.claude/agents`, and `CLAUDE.md` files. On
Windows it runs imported hook commands through PowerShell, so a hook written
for bash fails, and a failing `PreToolUse` hook **blocks the tool call**. With
the claude-mem plugin installed, every file write and read of a delegated run
was rejected (`Hook blocked with message: ... syntax error near unexpected
token`), so no edit was possible.

Isolated runs fix that by loading a tiny preload into Cursor's own Node
process that makes `os.homedir()` return `~/.cursor-rescue/home`, so Cursor
does not find `~/.claude` (nor your `~/.cursor` chats and MCP servers). The
environment of the commands the delegate runs is untouched — `USERPROFILE`,
`HOME`, `APPDATA` stay real, so git, SSH, NuGet, npm and the sign-in keep
working. Setup turns isolation on when it finds Claude Code plugins with hooks
on Windows; if a run still hits `Hook blocked with message`, the subagent
reruns it once isolated and tells you. On macOS/Linux hooks run under bash as
intended, and the isolation preload is not used (the sign-in path there
derives from the home directory).

## Known Cursor CLI behaviours this plugin works around

| Behaviour (2026.09.26–28) | Handling |
|---|---|
| `cursor-agent.cmd` passes arguments through `cmd.exe`, which cuts a multi-line prompt at the first line break and re-parses quotes | Windows: the bundled `node.exe` + `index.js` are called directly |
| `--model` is persisted as the default model of the config dir in use | plugin-owned `CURSOR_CONFIG_DIR`, and `--model` is always passed explicitly |
| Free plan: any named model fails with `ActionRequiredError: Named models unavailable` | `about` preflight reads the tier; Free → `auto` |
| Deny rules match only the first command of a shell call | wrapper shells and runners are denied too |
| Imported Claude Code hooks run through PowerShell on Windows and block tool calls when they fail | homedir preload isolates Cursor from `~/.claude` |
| No print-timeout; text output is printed only at the end, so a timeout loses everything | `timeout -k 10 540` + `stream-json` through a progress filter |
| `-p` with an open stdin pipe can wait forever | stdin is closed with `</dev/null` |
| Git Bash rewrites arguments that look like POSIX paths, so a task starting with `/` would reach Cursor mangled | `MSYS_NO_PATHCONV=1`, with Windows-style paths built by `pwd -W` / `cygpath -w` |
| Ask mode refuses edits and rejected shell commands | `--read-only` maps to ask mode; paste diffs into the task |

## What's in the plugin

| Piece | Purpose |
|---|---|
| `agents/cursor-rescue.md` | Thin forwarder subagent — one `cursor-agent -p` call, compact output |
| `/cursor:rescue` | Delegate a task explicitly (`--background`, `--wait`, `--model`, `--read-only`, `--isolate`) |
| `/cursor:setup` | Locate CLI, version, sign-in, plugin config dir + deny probe, isolation default, models |
| `docs/cli-config.json` | The plugin-owned config with the deny rules |
| `docs/claude-md-snippet.md` | Ready-to-paste CLAUDE.md block |
| `docs/delegation-guide.md` | Multi-lane orchestration guide |

## Not yet

- `--worktree` passthrough (`cursor-agent -w` creates an isolated git worktree
  under `~/.cursor/worktrees/`) — not verified yet.
- A Codex CLI skill variant (copilot-plugin-cc ships one).
- Quota gauge: Cursor's usage API exists, but the CLI exposes no headless
  usage command that the forwarder could read before a run.

## License

[MIT](LICENSE)

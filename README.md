# cursor-plugin-cc

Delegate coding tasks from [Claude Code](https://claude.com/claude-code) to
[Cursor Agent CLI](https://cursor.com/docs/cli/overview) (`cursor-agent`) in
headless mode.

Claude Code stays the orchestrator — it writes the domain logic, defines each
subtask contract, and reviews the diffs. The delegate is agentic: it reads and
edits files and runs commands in your repo itself, under a plugin-owned config
dir whose deny rules block the dangerous operations (see Safety model).
`--read-only` runs it in Cursor's ask mode for reviews and diagnoses that must
not touch the working tree. On Cursor's **Free plan only the `auto` model
runs** and turns are slow; paid plans can name any model `cursor-agent models`
lists.

> Lea esto en español: [README.es.md](README.es.md)

## When it helps

- **Its own quota.** Each delegated run spends agent requests from your Cursor
  plan's monthly allowance, not your Claude Code usage — useful when you want
  to spread work across both.
- **Bounded, fully-specified tasks.** One spec file, a rename, boilerplate,
  one build fix — work the delegate can finish without asking why.
- **Read-only second opinions.** `--read-only` runs Cursor's ask mode, which
  refuses file edits (and rejected shell commands in testing), so reviews and
  diagnoses stay out of your working tree. Paste the diff or code into the
  task.
- **Honest Free-plan limits.** Only `auto` runs — any named model fails — and
  turns are slow: in testing a trivial reply took 20–90 s and a run with eight
  shell commands did not finish in 9 minutes. Size tasks small.

Not for: domain logic, business rules, architecture decisions — anything where
the WHY lives in your conversation stays with the main thread.

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

## Setup

Then, once per machine:

```
/cursor:setup
```

Setup locates the CLI, checks version (floor **2026.09.26** — older suggests
`cursor-agent update`) and sign-in, creates the plugin-owned config dir
`~/.cursor-rescue/` with the deny rules every delegated run uses, optionally
verifies they bite (one agent request), decides whether delegated runs must be
isolated from your Claude Code plugins (Windows, see below), and lists the
models your plan can use.

Why its own dir: every delegated run sets `CURSOR_CONFIG_DIR` to
`~/.cursor-rescue/`, so the deny rules apply to delegated runs only and your
interactive Cursor sessions keep your own settings. It also contains a
`cursor-agent` quirk — the CLI saves the last `--model` as the default model
of the config dir it ran with, and a named model left in the user-level config
breaks every later run on the Free plan.

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
`auto` model on the Free plan is slow**, so size tasks small: one spec file,
one rename, one review.

### Resuming

The subagent adds `--continue` when your request clearly continues prior
Cursor work in this repo ("continue", "keep going", "resume"). Delegated runs
keep their own chat history (see isolation below on Windows), so `--continue`
picks up the last delegated run, not your interactive Cursor sessions.

### Proactive delegation

The `cursor-rescue` agent's description lets Claude Code use it on its own for
bounded tasks and read-only second opinions. That run sends the task text to
Cursor's backend and lets the model edit files in the current repository with
tool calls auto-approved (the deny rules still apply). What stands between that
and your working tree is Claude Code's own permission system: the subagent's
only tool is `Bash`, so in the default permission mode you approve the launch
command before it runs, while under bypass mode it runs unprompted. Whether
delegation happens proactively or only on request is your call — define it in
your `CLAUDE.md`. If you want delegation only on request, add this line to
`~/.claude/CLAUDE.md`:

```
Never launch cursor:cursor-rescue on your own; use it only when I invoke /cursor:rescue explicitly.
```

[docs/claude-md-snippet.md](docs/claude-md-snippet.md) is a ready-to-paste
starting block; adapt its triggers to your setup.

### What runs underneath

The subagent makes two Bash calls to `scripts/cursor-forward.sh`, which holds
every deterministic step (tested with a fake `cursor-agent` in `tests/run.sh`):

```bash
bash scripts/cursor-forward.sh preflight [--model <slug>] [--isolate|--no-isolate]
bash scripts/cursor-forward.sh run --model <slug> [--read-only] [--continue] <<'CURSOR_TASK_<nonce>'
<your task, verbatim>
CURSOR_TASK_<nonce>
```

`preflight` finds the launcher, checks the deny rules, reads version, plan and
sign-in with `cursor-agent about` (no agent turn) and picks the model (`auto`
on the Free plan). `run` then executes, simplified for the Windows bundle (on
macOS/Linux the launcher is `cursor-agent`):

```bash
CURSOR_CONFIG_DIR=~/.cursor-rescue MSYS2_ARG_CONV_EXCL='*' GIT_TERMINAL_PROMPT=0 \
GIT_SSH_COMMAND="ssh -o BatchMode=yes" NO_OPEN_BROWSER=1 \
timeout -k 10 540 "$VER/node.exe" --require scripts/cursor-preload.js "$VER/index.js" \
  -p "<task + constraints>" --output-format stream-json --trust --workspace "<repo>" \
  --force --model auto [--mode ask] [--continue] </dev/null 2>&1 | node scripts/stream-filter.js
```

and appends one `[cursor-rescue] WARNING: <what changed> — review before your
next git command` line when the run moved `HEAD`, switched branch, changed the
stash list, the git config or the hooks (it reports, it never reverts).

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
| `Shell(git push)`, `reset`, `clean`, `checkout`, `switch`, `restore`, `stash`, `rebase`, `commit`, `rm`, `worktree`, `config`, `filter-branch`, `filter-repo`, `update-ref`, `reflog`, `branch -D/-d`, `tag -d`, `gc`, `prune`, and git global options `-C`, `-c`, `--git-dir`, `--work-tree` | shared state, discarding work, history changes |
| `Shell(rm)`, `rmdir`, `del`, `erase`, `rd`, `ri`, `Remove-Item`, `unlink`, `shred` | deleting files |
| `Shell(bash)`, `sh`, `zsh`, `fish`, `dash`, `powershell`, `pwsh`, `cmd`, `wsl`, `env`, `xargs`, `Start-Process` | wrapper shells that hide the commands above |
| `Shell(sudo)`, `runas` | privilege escalation |
| `Shell(claude)`, `codex`, `copilot`, `agy`, `gemini`, `ollama`, `cursor-agent`, `agent`, `aider`, `opencode`, `amp`, `goose`, `qwen`, `crush` | recursive delegation to other AI CLIs |
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
- Git aliases already defined in your git config run under their alias name, so an alias that pushes is not caught by `Shell(git push)`; package runners such as `npx` can start any tool (including another AI CLI) behind an allowed first command. `find … -delete` and script-based deletion are not denied either.

**Review the diff.** The delegate's output is medium trust: an agentic model
did the work with tool calls auto-approved. Check `git status`, `git diff`,
`git log` and `git stash list` before committing; the orchestrator owns the
commit.

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

## Configuration

The plugin owns `~/.cursor-rescue/` (move it with `CURSOR_RESCUE_HOME`):

| File | Purpose |
|---|---|
| `cli-config.json` | Deny rules for delegated runs (template: `docs/cli-config.json`). The subagent refuses to run without the critical rules (exit 78). |
| `isolate` | `on` or `off` — isolation default written by setup (Windows). Override per run with `--isolate` / `--no-isolate`. |

Environment variables the forwarder understands (all optional):

| Variable | Purpose |
|---|---|
| `CURSOR_API_KEY` / `CURSOR_AUTH_TOKEN` | Sign in without `cursor-agent login`. |
| `CURSOR_RESCUE_HOME` | Move the plugin-owned config dir elsewhere. |
| `CURSOR_RESCUE_TIMEOUT` | Run cap in seconds (default 540). |
| `CURSOR_AGENT_BIN` | Use this `cursor-agent` binary instead of searching. |
| `CURSOR_AGENT_NODE` + `CURSOR_AGENT_INDEX` | Use this Windows bundle directly (`node.exe` + `index.js`). |

Model selection: pass `--model <slug>` with any slug `cursor-agent models`
lists (setup shows them); on the Free plan the preflight switches to `auto`
and says so. `--model` is always passed explicitly, and thanks to
`CURSOR_CONFIG_DIR` it is remembered only inside `~/.cursor-rescue/`.

Repository layout:

| Piece | Purpose |
|---|---|
| `agents/cursor-rescue.md` | Thin forwarder subagent — `preflight` and `run` calls, output returned as-is |
| `scripts/cursor-forward.sh` | Launcher discovery, deny gate, plan/model preflight, isolation, timeout, git-change warnings |
| `scripts/stream-filter.js` | `stream-json` → compact progress log |
| `scripts/cursor-preload.js` | Windows bundle only (`node --require`): clears the MSYS variable inside Cursor and, when isolating, points `os.homedir()` away from `~/.claude` |
| `tests/run.sh` | Hermetic tests with a fake `cursor-agent` — `bash tests/run.sh` |
| `/cursor:rescue` | Delegate a task explicitly (`--background`, `--wait`, `--model`, `--read-only`, `--isolate`) |
| `/cursor:setup` | Locate CLI, version, sign-in, plugin config dir + deny probe, isolation default, models |
| `docs/cli-config.json` | The plugin-owned config with the deny rules |
| `docs/claude-md-snippet.md` | Ready-to-paste CLAUDE.md starting block |
| `docs/delegation-guide.md` | Delegation guide (works with Cursor alone or next to other delegates) |

## Troubleshooting

Every row below is a behaviour verified on 2026.09.26–28 (Windows 11) plus the
handling the plugin applies.

| Symptom | Cause | Handling |
|---|---|---|
| Multi-line prompt arrives cut at the first line break | `cursor-agent.cmd` passes arguments through `cmd.exe`, which re-parses quotes | On Windows the bundled `node.exe` + `index.js` are called directly |
| Interactive sessions break after a named-model run | `--model` is persisted as the default model of the config dir in use | Plugin-owned `CURSOR_CONFIG_DIR`, and `--model` is always passed explicitly |
| `ActionRequiredError: Named models unavailable` | Free plan with a named model | The `about` preflight reads the tier; Free → `auto`. If it still slips through, the subagent reruns once on `auto` |
| `rm` denied but `bash -c "rm …"` deletes anyway | Deny rules match only the first command of a shell call | Wrapper shells and runners are denied too — still a guardrail, not a sandbox |
| `Hook blocked with message` on every file read and write | Imported Claude Code hooks run through PowerShell on Windows and block tool calls when they fail | The homedir preload isolates Cursor from `~/.claude`; the subagent reruns once isolated (run `/cursor:setup` to make isolation the default) |
| Run cut at 9 minutes with partial output | No print-timeout; text output prints only at the end | `timeout -k 10 540` + `stream-json` through a progress filter, so partial progress survives |
| Run hangs without output | `-p` with an open stdin pipe can wait forever | Stdin is closed with `</dev/null` |
| Task starting with `/` reaches Cursor mangled | Git Bash rewrites arguments that look like POSIX paths | `MSYS2_ARG_CONV_EXCL='*'` with native paths built by `cygpath -m`. Not `MSYS_NO_PATHCONV=1`: that also stops converting path-like environment variables, and inherited by the delegate it left native `git` blind to `GIT_CONFIG_GLOBAL` (caught by the tests). The preload removes the variable inside Cursor, so the delegate's own commands convert paths normally (verified) |
| Ask-mode run edits nothing and reports little | Ask mode refuses edits and rejected shell commands | `--read-only` maps to ask mode; paste diffs into the task |
| `[cursor-rescue] WARNING: …` after a run | The delegate moved `HEAD`, switched branch, or changed the stash list, git config or hooks | `run` compares them before and after and prints one line per change — review before your next git command |
| `[cursor-rescue] task is N characters, over the 30000 limit` (exit 64) | The whole task travels as one command-line argument; Windows caps a command line at 32767 characters | Tasks over 30000 characters are refused before anything runs — reference files by path or split the task |
| `preflight failed: not signed in` (exit 70) | No sign-in found | Run `cursor-agent login` once (or export `CURSOR_API_KEY`), then `/cursor:setup` |
| `[cursor-rescue] Cursor quota or plan limit hit` | Usage limit, rate limit, `429`, or plan allowance used up | The subagent stops and never retries — continue inline or with another delegate, and say so once |
| `cursor-agent not found` (exit 127) | CLI not installed or not on PATH | Install it (see Requirements), then `/cursor:setup` |
| `missing deny rules` (exit 78) | `~/.cursor-rescue/cli-config.json` absent or incomplete | Run `/cursor:setup` to recreate or repair it |

Known limits: no `--worktree` passthrough yet (`cursor-agent -w` creates an
isolated git worktree under `~/.cursor/worktrees/` — not verified), and no
quota gauge — the CLI exposes no headless usage command, so quota detection
is reactive (see the quota row above).

## Using it with other delegates

This plugin assumes no order between delegates: if you run several, you define
each one's triggers and fallbacks in your `CLAUDE.md`. On quota, usage-limit
or sign-in signals the subagent stops and reports them, so the caller can pick
another way forward. Related projects by the same author, no ranking implied:
[copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc),
[antigravity-plugin-cc](https://github.com/santiquiroz/antigravity-plugin-cc),
[ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc),
[bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc) — all
inspired by [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).

## License

[MIT](LICENSE). **Not affiliated with Cursor (Anysphere), OpenAI, GitHub,
Google or Anthropic.**

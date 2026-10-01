# Changelog

## 0.2.0 — 2026-09-30

- Move every deterministic step out of the subagent prompt into
  `scripts/cursor-forward.sh` (`preflight`, `run`, `models`), the pattern the
  sibling plugins use: the subagent no longer assembles a hundred lines of
  bash per call. The progress filter and the Windows isolation preload are
  plain files under `scripts/`.
- The task travels on stdin through a heredoc whose delimiter carries a fresh
  random suffix per call; a task line equal to a fixed delimiter would close
  the heredoc early and run the rest of the task as shell commands.
- `run` warns when the delegate moved `HEAD`, switched branch, changed the
  stash list, the git config or the hooks, and refuses tasks over 30000
  characters (the Windows command-line limit) before anything runs.
- The deny gate checks a dozen critical rules by name instead of the mere
  presence of a `deny` key.
- Fix the delegate's native tools losing path-like environment variables on
  Windows: 0.1.0 exported `MSYS_NO_PATHCONV=1`, which Cursor passed on to the
  commands it ran, so e.g. `git` no longer saw `GIT_CONFIG_GLOBAL`. The task
  argument is now protected with `MSYS2_ARG_CONV_EXCL`, which a preload
  (`scripts/cursor-preload.js`, always loaded with the Windows bundle) removes
  inside Cursor before any command runs.
- `/cursor:setup` drives the same script, so it checks exactly what a
  delegation will hit.
- `tests/run.sh`: hermetic tests with a fake `cursor-agent`.

## 0.1.0 — 2026-09-30

First release, verified on Cursor Agent CLI 2026.09.26 and 2026.09.28
(Windows 11, Git Bash, Free plan).

- `cursor-rescue` subagent: thin forwarder that runs `cursor-agent -p` headless
  with `--force`, `--trust`, an explicit `--model` and a 9-minute `timeout`,
  and returns a compact progress log built from `stream-json`, so a run cut
  by the timeout still shows what it did.
- Plugin-owned config dir (`CURSOR_CONFIG_DIR=~/.cursor-rescue`): deny rules
  apply to delegated runs only, and a `--model` passed to a delegated run no
  longer becomes the default model of your interactive Cursor sessions.
- Deny list covering push/reset/checkout/commit and other history-changing git
  commands, git global options that reorder arguments (`-C`, `-c`), file
  deletion, wrapper shells (`bash -c "rm …"` got past a plain `rm` deny in
  testing), privilege escalation, other AI CLIs and writes under `.git/`.
- Windows: calls the bundled `node.exe` directly (the `.cmd` shim cuts
  multi-line prompts), disables MSYS path conversion, and can isolate Cursor
  from `~/.claude` with an `os.homedir()` preload — imported Claude Code hooks
  run through PowerShell and blocked every file read and write.
- Free plan: `about` preflight reads the tier and runs `auto` instead of a
  named model.
- `--read-only` maps to Cursor's ask mode.
- `/cursor:rescue` and `/cursor:setup` commands, CLAUDE.md snippet and
  delegation guide.

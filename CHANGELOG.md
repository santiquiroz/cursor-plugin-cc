# Changelog

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

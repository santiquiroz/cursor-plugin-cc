# CLAUDE.md snippet

Paste the block below into your `~/.claude/CLAUDE.md` (or a project
`CLAUDE.md`) to make Claude Code delegate to Cursor proactively. Adjust the
trigger table to the lanes you actually run — the block assumes other
delegates may exist (a reasoning lane such as the codex plugin, a mechanical
lane such as the copilot plugin) and slots Cursor in as an extra agentic lane.
See [delegation-guide.md](delegation-guide.md) for the full split.

```markdown
# Cursor Agent CLI delegation (cursor plugin)

Cursor (`cursor-agent`) is an extra agentic lane on Cursor's own quota.
Subagent `cursor:cursor-rescue`; commands `/cursor:rescue`, `/cursor:setup`.
The delegate reads and edits files and runs commands in the repo, with tool
calls auto-approved and plugin-owned deny rules (`~/.cursor-rescue/`) blocking
push, reset, checkout, commit, file deletion and wrapper shells. Free plan:
only the `auto` model, slow turns, monthly request allowance.

| Trigger | Action |
|---|---|
| Mechanical or bounded task (spec file, rename, boilerplate, one build fix) and the usual lane for it is out of quota or busy | `cursor:cursor-rescue` in background |
| Independent read-only second opinion — review code, cross-check a diagnosis | `cursor:cursor-rescue` in background with `--read-only`; paste the diff or code into the task (ask mode does not run shell commands) |
| Output starts with `[cursor-rescue] Free plan only runs auto` or `reran isolated` | The subagent adjusted the run once; pass the result through |
| Output says `Cursor quota or plan limit hit`, or a sign-in error | Nothing more will run on Cursor. Fall back to the next lane or inline, and say so once |

Never delegate: domain logic, business rules, architecture decisions,
anything where the WHY lives in this conversation.

Rules:
- The task text must be self-contained — file paths, signatures, acceptance
  criteria. The delegate does not see this conversation.
- Keep tasks small: one run is capped at 9 minutes and Free-plan turns are slow.
- Review `git status` and `git diff` before committing; the orchestrator owns
  the commit.
- Run `/cursor:setup` once per machine; the subagent refuses to run without the
  plugin config dir and its deny rules.
- Launch in the background and keep working. WIP cap 3–5 concurrent
  delegations. Kill-switch: 3 failed iterations on the same task → stop
  retrying that lane.
```

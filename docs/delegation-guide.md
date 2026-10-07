# Delegation Guide

How to make Claude Code delegate work to Cursor Agent CLI (this plugin),
so the main thread stays focused on the work only it can do. Claude Code
stays the orchestrator.

## What Cursor is good for

Bounded, fully-specified tasks — work the delegate can finish without
asking why:

- One spec file, a rename, boilerplate, one build fix.
- Read-only second opinions: `--read-only` runs Cursor's ask mode, which
  refuses file edits and, in testing, rejected shell commands too — so
  paste the diff or code into the task instead of asking Cursor to run
  `git diff` itself.

Never delegate: domain logic, business rules, architecture decisions —
anything where the WHY lives in your conversation stays with the main
thread.

Rule of thumb: if the delegate needs to understand *why*, keep it inline.
If it is bounded and fully specified, delegate it.

## Know the Free plan limits

- Only the `auto` model runs — any named model fails. The subagent
  switches to `auto` on its own and says so in the first line.
- Turns are slow: in testing a trivial reply took 20–90 s.
- Agent requests count against a monthly allowance, and the CLI exposes
  no headless usage meter, so quota detection is reactive (see below).
- Every run is capped at 9 minutes. A run with eight shell commands did
  not finish in the cap during testing; one spec file did. Keep tasks
  small: one deliverable per run.

## Writing the task

- Self-contained: file paths, signatures, expected behaviour, acceptance
  checks (the exact test command to run). The delegate does not see your
  conversation.
- One deliverable per run.
- For `--read-only`, paste the code or the diff into the task: ask mode
  refuses edits and rejected shell commands in testing, so it cannot run
  `git diff` itself.

## The parallel pattern

```
Claude: writes SomeHandler (domain logic — inline, never delegated)
  → /cursor:rescue --background "add unit tests for src/utils/money.ts (signatures below) ..."
  → /cursor:rescue --background --read-only "review this diff for race conditions: <diff>"
Claude: continues with the next task while delegations run
```

- WIP cap: 3–5 concurrent background runs. Never run two of them on the
  same files at the same time.
- Kill-switch: after 3 stuck or failed attempts on the same task, stop
  retrying and take it inline.

## Safety rules

- `/cursor:setup` creates `~/.cursor-rescue/cli-config.json` with deny rules
  (push, reset, checkout, commit, file deletion, wrapper shells, other AI
  CLIs, writes under `.git/`). The subagent refuses to run without it. The
  rules apply to delegated runs only.
- Deny rules match the first command of a shell call. Interpreters such as
  `node` and `python` stay allowed, so this is a guardrail, not a sandbox.
- Review `git status`, `git diff`, `git log` and `git stash list` after every
  run. The orchestrator owns the commit.
- Do not delegate tasks that process untrusted content (web pages, issue
  text from strangers): web tools and network commands are available to the
  delegate.

## Quota and sign-in errors

**Detection:** the subagent prints `[cursor-rescue] Cursor quota or plan
limit hit` when the output mentions a usage or rate limit, `quota`, `429`, or
a plan allowance being used up. Sign-in errors ask for `cursor-agent login`.

- **Named model on the Free plan** → the subagent runs `auto` instead and
  says so in the first line. Nothing to do.
- **`[cursor-rescue] Cursor quota or plan limit hit`, or a sign-in
  error** → stop, do not retry, and tell the user in one line.

## Second opinions, not second drafts

Use `--read-only` when a tricky change or an ambiguous diagnosis benefits
from an independent pass. Feed it the same self-contained contract and the
code or diff, compare the answer with your own, and reconcile in the main
thread.

## Using it with other delegates

If you run several delegation plugins, the order between them is yours to
define in your own `CLAUDE.md`. This plugin does not assume any other
delegate exists.

# Multi-Agent Delegation Guide

How to make Claude Code delegate work to Cursor Agent CLI (this plugin) as an
extra agentic lane next to whatever other delegates you run — so the main
Claude thread stays focused on the work only it can do. Claude Code stays the
orchestrator.

## Which setup do you have?

- **Cursor next to other lanes** (e.g. a reasoning delegate such as the codex
  plugin, a mechanical one such as the copilot plugin): Cursor absorbs bounded
  tasks when those lanes are out of quota or busy, and gives read-only second
  opinions.
- **Cursor alone**: Cursor takes every delegable bounded task. Keep tasks
  small, especially on the Free plan, where only `auto` runs and turns are
  slow.

Everything on the never-delegate list stays inline with Claude in both cases.

## The core split

| Lane | Owns | Examples |
|---|---|---|
| **Reasoning delegate** (e.g. Codex) | Deep diagnosis, multi-step build fixing, architecture-adjacent code | Complex build errors after a failed fix, multi-file refactors changing control flow |
| **Cursor (this plugin)** | Bounded agentic tasks on Cursor's quota; read-only second opinions | One spec file, a rename, boilerplate, one build fix; `--read-only` review of a pasted diff |
| **Mechanical delegate** (e.g. Copilot) | Purely mechanical, zero-domain-context work | CRUD/mapping specs, renames across 3+ files, dead-code cleanup |
| **Keep inline (never delegate)** | Tasks where the WHY lives in your conversation | Domain logic, business rules, architecture and feature design |

Rule of thumb: if the delegate needs to understand *why*, keep it inline. If
it is bounded and fully specified, delegate it.

## Writing the task

- Self-contained: file paths, signatures, expected behaviour, acceptance
  checks (the exact test command to run). The delegate does not see your
  conversation.
- One deliverable per run. A Free-plan run with eight shell commands did not
  finish in the 9-minute cap during testing; one spec file did.
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

- WIP cap: 3–5 concurrent background delegations across all lanes. Never run
  two delegates on the same files at the same time.
- Kill-switch: after 3 stuck or failed iterations on the same task, stop
  retrying that lane; hand the task to another lane once or take it inline.

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

## Quota fallback chain

**Detection:** the subagent prints `[cursor-rescue] Cursor quota or plan
limit hit` when the output mentions a usage or rate limit, `quota`, `429`, or
a plan allowance being used up. Sign-in errors ask for `cursor-agent login`.

1. **Named model on the Free plan** → the subagent runs `auto` instead and
   says so in the first line. Nothing to do.
2. **Cursor quota or plan limit hit** → nothing more runs on Cursor this
   period. Hand the task to another lane once if it fits, otherwise do it
   inline. Never retry in a loop.
3. **Every lane exhausted** → stop auto-delegating for the rest of the
   session, handle everything inline, and mention it once.

Tell the user in one line when a fallback happened — which lane failed and
which one picked the task up, or that Claude took over inline.

## Second opinions, not second drafts

Use `--read-only` when a tricky change or an ambiguous diagnosis benefits
from an independent pass. Feed it the same self-contained contract and the
code or diff, compare the answer with your own, and reconcile in the main
thread.

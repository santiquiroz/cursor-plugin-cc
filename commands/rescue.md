---
description: Delegate a well-specified coding task to Cursor Agent CLI (cursor-agent) through the cursor-rescue subagent
argument-hint: "[--background|--wait] [--model <slug>] [--read-only] [--isolate|--no-isolate] [the task Cursor should perform]"
allowed-tools: AskUserQuestion, Agent
---

Invoke the `cursor:cursor-rescue` subagent via the `Agent` tool (`subagent_type: "cursor:cursor-rescue"`), forwarding the raw user request as the prompt.
`cursor:cursor-rescue` is a subagent, not a skill — do not call it via the `Skill` tool. This command runs inline so the `Agent` tool stays in scope.
The final user-visible response must be the subagent's output verbatim.

Raw user request:
$ARGUMENTS

Execution mode:

- If the request includes `--background`, run the subagent in the background and continue other work; relay the result when it completes.
- If the request includes `--wait`, run the subagent in the foreground.
- If neither flag is present, default to foreground.
- `--background` and `--wait` are execution flags for Claude Code. Do not forward them in the prompt, and do not treat them as part of the natural-language task text.
- `--model <slug>`, `--read-only`, `--isolate` and `--no-isolate` are runtime flags. Preserve them in the forwarded prompt (the subagent maps them to `cursor-agent` flags and environment), but do not treat them as part of the natural-language task text.

Operating rules:

- The subagent is a thin forwarder only. It uses one `Bash` call to run `cursor-agent -p ...` headless against the current repo, and returns that command's output as-is.
- Before dispatching, make sure the task text is self-contained: paste in the file paths, signatures and acceptance criteria it refers to. The delegate does not see this conversation.
- For reviews, diagnoses and second opinions that must not touch the working tree, add `--read-only` (Cursor's ask mode, which refuses to edit).
- Return the output verbatim to the user. Do not paraphrase, summarize, rewrite, or add commentary before or after it.
- Do not ask the subagent to inspect files, monitor progress, summarize output, or do follow-up work of its own.
- If the returned output says `cursor-agent` is not installed, not signed in, or that the plugin config dir has no deny rules, tell the user to run `/cursor:setup`.
- If the returned output starts with `[cursor-rescue]`, the subagent already adjusted the run once (model switched to `auto`, or a rerun isolated from `~/.claude`); pass the result through as-is. If it says the Cursor quota or plan limit was hit, nothing more will run on Cursor — hand the task to another delegate or take it inline, and say so once. Do not retry automatically.
- If the user did not supply a task, ask what task Cursor should perform.

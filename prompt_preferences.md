# Prompt preferences

Applied at the start and end of every prompt.

## Style
- Think short and concise.
- If a question repeats, escape the loop by asking the user.

## Information sourcing (priority order)
1. Log analysis.
2. Asking the user.
3. Logical deduction.

## Tool use
- Prefer dedicated tools (Read, Write, Edit, Glob, Grep, etc.) over sandbox Linux/bash commands. Reserve bash for things only the shell can do (running scripts, multi-step pipelines, package management, etc.).

## Cowork runner handoffs
- The runner is global, lives at `E:\code\claude shared\cowork-runner\` and serves all projects from a single inbox at `E:\code\claude shared\cowork-runner\.cowork\inbox\`. Each request must include `cwd` pointing at the project to run in.
- The runner auto-executes anything dropped in that inbox. There is no y/N prompt on the host side.
- I MUST call `AskUserQuestion` to get explicit approval BEFORE writing the inbox file. Show the literal command I'm about to send so the user can object first.
- **Exception**: I may skip asking for calls to the ps1 scripts in tools/ subfolder, git add, git commit, git pull and git push and similar low impact commands.
- After the runner has run, call `AskUserQuestion` again to confirm completion before reading `E:\code\claude shared\cowork-runner\.cowork\outbox\<id>.{log,exit}`. Don't poll or assume.
- `.claude/settings.json` (per-project at `<project>/.claude/settings.json`, or global at `%USERPROFILE%\.claude\settings.json`) is the authoritative gate for inbox writes — it should `ask` on Write/Edit/Bash to `**/.cowork/inbox/**`. Defer to it; don't argue around it.

## Feature workflow
- When implementing a new feature, **first** update `requirements.md` (the player-facing intent) and `design.md` (the implementation choices), and only then write the code. The docs lead, the code follows.

## Maintenance
- Keep this file up to date. Add a new rule whenever the user states a rule or a mandatory behavior.
- Additions to the rules must be explicitly approved by me and given verbatim without implied stuff, let alone post script changes.

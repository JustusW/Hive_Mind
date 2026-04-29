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
- The runner auto-executes any request I drop in `.cowork/inbox/`. There is no y/N prompt on the host side.
- I MUST call `AskUserQuestion` to get explicit approval BEFORE writing the inbox file. Show the literal command I'm about to send so the user can object first.
- After the runner has run, call `AskUserQuestion` again to confirm completion before reading `.cowork/outbox/<id>.{log,exit}`. Don't poll or assume.

## Maintenance
- Keep this file up to date. Add a new rule whenever the user states a rule or a mandatory behavior.

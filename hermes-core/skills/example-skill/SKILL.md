---
name: example-skill
description: Template showing the structure of a Hermes skill. Copy it, rename it, and rewrite every section. Not meant to be triggered; delete once real skills exist.
---

# Example Skill

## When to use
State the situation that should trigger this skill, in one or two lines. Be specific: this text decides whether the agent loads it.

## Procedure
1. One imperative, checkable action per step.
2. Name the exact tool or command (for example `fetch` MCP, `hermes cron list`).
3. Say what to do when a step fails.

## Pitfalls
- What went wrong before and how to avoid it.

## Verification
- How to confirm the work is done (a command whose output you can read).

<!-- Rules: `name` equals the directory name; no secrets; keep under ~150 lines; use references/ and scripts/ for bulk. -->

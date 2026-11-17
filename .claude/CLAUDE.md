# zero-coding-agent

Goal: run a resident agent on $0 inference (free-tier LLM APIs). Hermes Agent (Nous Research) is the centre; everything else supports it.

## Layout
- `hermes-core/config.yaml`: MCP servers and skill dirs for Hermes (secrets via `${ENV_VAR}`, never inline).
- `hermes-core/skills/<name>/SKILL.md`: agentskills.io skills. Frontmatter `name` must equal the directory name.
- `deploy/`: install and ops scripts (idempotent, `set -euo pipefail`).
- `.claude/`: Claude Code config, hooks, slash commands (`/new-mcp`, `/new-skill`, `/ship`).

## Rules
- Never commit `.env`, `*.sqlite`, `browser-profiles/`. A hook blocks it; `.gitignore` covers it. `.env.example` is allowed.
- Never put API keys in any tracked file. Reference env vars.
- Free-tier quotas change. Date-stamp any quota figure and mark it unverified until checked at the provider.
- Do not invent model IDs. Read them from the provider's current model list.
- Docs: Hermes at https://hermes-agent.nousresearch.com/docs (MCP: reference/mcp-config-reference, skills: user-guide/features/skills, cron: user-guide/features/cron). Use the `context7` MCP for library docs.
- Edited `.py`, `.yaml`, `.sh` files are syntax-checked automatically; fix reported errors before moving on.
- Commit style: Conventional Commits. Do not push unless asked.

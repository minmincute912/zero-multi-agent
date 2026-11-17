# zero-coding-agent

Goal: run a resident agent on $0 inference (free-tier LLM APIs). Hermes Agent (Nous Research) is the centre; everything else supports it.

## Layout
- `hermes-core/`: `config.yaml` (model, MCP servers, skill dir; secrets via `${ENV_VAR}`, never inline), `SOUL.md`, `skills/<name>/SKILL.md` (agentskills.io; frontmatter `name` must equal the directory name).
- `docker-services/`: `docker-compose.yml`, `inference-router/` (LiteLLM, model groups light/heavy/coder), `mcp-web-worker/`, `node-control-plane/`. Ports bind 127.0.0.1 only.
- `mcp-plugins/_template/`: copy to create a new MCP service. MCP SDK is v2 (`MCPServer`, Streamable HTTP at `/mcp`, not SSE).
- `deploy/`: `setup-vps.sh`, `update-vps.sh`, other ops scripts (idempotent, `set -euo pipefail`).
- `.github/workflows/gitops-deploy.yml`: lint/test, GHCR build, VPS sync. See `README.md` for architecture and operations.
- `.claude/`: Claude Code config, hooks, slash commands (`/new-mcp`, `/new-skill`, `/ship`).

## Rules
- Never commit `.env`, `*.sqlite`, `browser-profiles/`. A hook blocks it; `.gitignore` covers it. `.env.example` is allowed.
- Never put API keys in any tracked file. Reference env vars.
- Free-tier quotas change. Date-stamp any quota figure and mark it unverified until checked at the provider.
- Do not invent model IDs. Read them from the provider's current model list.
- Docs: Hermes at https://hermes-agent.nousresearch.com/docs (MCP: reference/mcp-config-reference, skills: user-guide/features/skills, cron: user-guide/features/cron). Use the `context7` MCP for library docs.
- Edited `.py`, `.yaml`, `.sh` files are syntax-checked automatically; fix reported errors before moving on.
- Commit style: Conventional Commits. Do not push unless asked.

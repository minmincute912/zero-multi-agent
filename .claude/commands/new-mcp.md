---
description: Add an MCP server entry to hermes-core/config.yaml
argument-hint: <name> <stdio|sse|http> <command-or-url>
---

Add MCP server `$ARGUMENTS` to `hermes-core/config.yaml` under `mcp_servers`.

1. Read `hermes-core/config.yaml` first. Stop and report if the name already exists.
2. Check the schema at https://hermes-agent.nousresearch.com/docs/reference/mcp-config-reference (do not rely on memory).
3. Shape:
   - stdio: `command`, `args`, `env`
   - http: `url`, `headers`
   - sse: `url` plus `transport: sse`
   - always `timeout` and `enabled`; restrict with `tools.include` when the server exposes risky tools.
4. Secrets go in `env`/`headers` as `${VAR}` references. Add the variable name (no value) to `.env.example`.
5. Validate with `python3 -c "import yaml;yaml.safe_load(open('hermes-core/config.yaml'))"`.
6. Report the entry and remind the user to run `/reload-mcp` in Hermes.

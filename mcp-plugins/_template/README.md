# MCP plugin template

Copy this directory to create a new MCP microservice. It is built on the VPS by `docker compose up --build`; there is no registry.

## Create a plugin

1. `cp -r mcp-plugins/_template mcp-plugins/<name>` and edit `manifest.json` (`name` must equal the directory name).
2. Replace the example tools in `server.py`. Read secrets from environment variables only.
3. Add a service to `docker-services/docker-compose.yml`:

   ```yaml
   <name>:
     <<: *common
     build: ../mcp-plugins/<name>
     ports: ["127.0.0.1:<host-port>:8000"]
     mem_limit: 256m
     cpus: 0.5
     healthcheck:
       test: ["CMD", "python3", "-c", "import socket; socket.create_connection(('127.0.0.1', 8000), 3)"]
       interval: 30s
       timeout: 5s
       retries: 3
   ```

4. Register it in `hermes-core/config.yaml` under `mcp_servers` (or run `/new-mcp`):

   ```yaml
   <name>:
     url: "http://127.0.0.1:<host-port>/mcp"
     timeout: 120
     enabled: true
   ```

5. Run locally: `python server.py`, then connect an MCP client to `http://127.0.0.1:8000/mcp`.

## Rules

- Bind published ports to `127.0.0.1` only.
- Validate every tool argument. A tool is reachable by prompt-injected text, so never pass arguments to a shell
  or fetch arbitrary URLs without an allowlist.
- Keep the MCP SDK on `mcp>=2.3,<3`: v2 renamed `FastMCP` to `MCPServer` and prefers Streamable HTTP over SSE.

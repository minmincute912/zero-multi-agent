---
name: ops-sentinel
description: Set up and run a cron health check for the VPS, container RAM and satellite nodes (mcp-web-worker, node-control-plane), alerting only on problems. Use when asked to monitor the server, after deploying containers, or when the agent or an MCP server becomes unresponsive.
---

# Ops Sentinel

Health checks must cost no tokens: use a script-only cron job (`--no-agent`). The agent is involved only to diagnose an alert.

## When to use
- Setting up monitoring on a new VPS.
- An MCP server, container or the gateway stopped responding.
- Answering "is the server OK?".

## Procedure
1. **Install the check script** at `~/.hermes/scripts/ops-check.sh` (Hermes only accepts scripts from that directory) and `chmod +x` it. It prints nothing when healthy, so the job stays silent:
   ```bash
   #!/usr/bin/env bash
   set -u
   mem=$(LC_ALL=C free | awk '/Mem:/ {printf "%d", $3*100/$2}')
   disk=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')
   [ "$mem"  -ge 85 ] && echo "RAM ${mem}% used"
   [ "$disk" -ge 85 ] && echo "Disk ${disk}% used"
   docker stats --no-stream --format '{{.Name}} {{.MemPerc}}' 2>/dev/null |
     awk '{p=$2; sub("%","",p); if (p+0 >= 85) print "container " $1 " RAM " $2}'
   for hp in localhost:4000 localhost:8001 localhost:8002; do
     curl -s -o /dev/null --max-time 3 "http://$hp/" \
       || [ $? -eq 28 ] || echo "service $hp unreachable"
   done
   ```
   Any HTTP answer counts as alive (curl exits 0 even on 4xx). Exit 28 (timeout) is accepted because a Streamable HTTP endpoint may hold the connection open. Ports: 4000 inference-router, 8001 mcp-web-worker, 8002 node-control-plane. For remote satellite nodes, call the `node-control-plane` `health_check` tool instead.
2. **Schedule it**:
   ```
   hermes cron create "every 5m" --no-agent --script ops-check.sh --deliver <channel> --name "ops-sentinel"
   ```
   Use the channel the user already configured (for example `telegram`).
3. **Manage**: `hermes cron list`, `pause <id>`, `resume <id>`, `remove <id>`.
4. **On an alert**, diagnose with read-only commands first: `docker ps`, `docker logs --tail 50 <name>`, `free -h`, `df -h`. Report findings and the proposed fix.

## Pitfalls
- Do not restart containers, kill processes or delete files without the user's approval.
- Alert fatigue: keep thresholds high (85%) and the job silent when healthy.
- Passing a command string to `--script` is rejected; it must be a file in `~/.hermes/scripts/`.
- A failing script sends an error notification, which is intended. Do not hide errors with `|| true` on the whole script.

## Verification
- `hermes cron list` shows `ops-sentinel`.
- Force a test: temporarily lower a threshold to 1 and confirm one alert arrives, then restore it.

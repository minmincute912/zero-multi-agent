"""node-control-plane: MCP server that health-checks, meters and dispatches jobs to satellite nodes.

Only nodes registered in nodes.yaml can be contacted, so a prompt-injected agent cannot make this service call
arbitrary URLs. Jobs are HMAC-signed with a per-node secret read from the environment.
"""
import hashlib
import hmac
import json
import os
import pathlib
import time
from datetime import UTC, datetime

import httpx
import yaml
from mcp.server.mcpserver import MCPServer

CONFIG = pathlib.Path(os.environ.get("NODES_FILE", "/config/nodes.yaml"))
STATE = pathlib.Path(os.environ.get("STATE_FILE", "/data/state.json"))
MAX_PAYLOAD = 64 * 1024

mcp = MCPServer("node-control-plane")


def _nodes() -> dict:
    if not CONFIG.exists():
        return {}
    data = yaml.safe_load(CONFIG.read_text()) or {}
    return {n["name"]: n for n in data.get("nodes", []) if n.get("enabled", True)}


def _today() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%d")


def _load_state() -> dict:
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}


def _used(state: dict, name: str) -> int:
    entry = state.get(name, {})
    return entry.get("count", 0) if entry.get("day") == _today() else 0


def _node(name: str) -> dict:
    nodes = _nodes()
    if name not in nodes:
        raise ValueError(f"unknown or disabled node {name!r}; known: {sorted(nodes)}")
    return nodes[name]


@mcp.tool()
def list_nodes() -> list[dict]:
    """List registered satellite nodes with their kind and today's usage against the daily limit."""
    state = _load_state()
    return [
        {"name": n["name"], "kind": n.get("kind"), "daily_limit": n.get("daily_limit"), "used_today": _used(state, n["name"])}
        for n in _nodes().values()
    ]


@mcp.tool()
def quota_status() -> dict:
    """Per-node jobs used today (UTC) versus the configured daily limit."""
    state = _load_state()
    return {
        n["name"]: {"used": _used(state, n["name"]), "limit": n.get("daily_limit")}
        for n in _nodes().values()
    }


@mcp.tool()
def health_check(node: str | None = None) -> list[dict]:
    """HTTP health-check one node, or all registered nodes when `node` is omitted."""
    targets = [_node(node)] if node else list(_nodes().values())
    results = []
    for n in targets:
        url = n["url"].rstrip("/") + n.get("health_path", "/health")
        start = time.monotonic()
        try:
            r = httpx.get(url, timeout=5)
            results.append({"name": n["name"], "ok": r.is_success, "status": r.status_code,
                            "ms": round((time.monotonic() - start) * 1000)})
        except httpx.HTTPError as e:
            results.append({"name": n["name"], "ok": False, "error": type(e).__name__})
    return results


@mcp.tool()
def dispatch_job(node: str, payload: dict) -> dict:
    """Send a JSON job to a registered node. Signed with HMAC-SHA256 in the X-Signature header.

    Refuses when the payload exceeds 64 KB, the node's daily limit is reached, or its secret is not configured.
    """
    n = _node(node)
    body = json.dumps(payload, separators=(",", ":")).encode()
    if len(body) > MAX_PAYLOAD:
        raise ValueError(f"payload {len(body)} bytes exceeds {MAX_PAYLOAD}")
    secret = os.environ.get(n.get("secret_env", ""), "")
    if not secret:
        raise ValueError(f"secret env var {n.get('secret_env')!r} for node {node!r} is not set")

    state = _load_state()
    limit = n.get("daily_limit")
    if limit is not None and _used(state, node) >= limit:
        raise ValueError(f"daily limit {limit} reached for {node}; retry after 00:00 UTC")

    sig = "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    url = n["url"].rstrip("/") + n.get("job_path", "/jobs")
    r = httpx.post(url, content=body, headers={"Content-Type": "application/json", "X-Signature": sig}, timeout=30)

    state[node] = {"day": _today(), "count": _used(state, node) + 1}
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state))  # shortcut: single writer assumed, upgrade to SQLite if jobs run concurrently
    return {"status": r.status_code, "body": r.text[:2000]}


if __name__ == "__main__":
    mcp.run("streamable-http", host="0.0.0.0", port=8002)

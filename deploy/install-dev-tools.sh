#!/usr/bin/env bash
# Install dev tooling for Claude Code in this repo. Idempotent.
#  - context7 MCP server (project scope, writes .mcp.json)
#  - reports gh CLI status (does not install it)
set -euo pipefail
cd "$(dirname "$0")/.."

command -v claude >/dev/null || { echo "ERROR: claude CLI not found" >&2; exit 1; }
command -v npx    >/dev/null || { echo "ERROR: npx (Node.js) not found; context7 needs it" >&2; exit 1; }

if grep -q '"context7"' .mcp.json 2>/dev/null; then
  echo "context7: already configured"
else
  claude mcp add --scope project context7 -- npx -y @upstash/context7-mcp
  echo "context7: added (restart Claude Code to load it)"
fi

if command -v gh >/dev/null; then
  if gh auth status >/dev/null 2>&1; then
    echo "gh: installed and authenticated"
  else
    echo "gh: installed but NOT authenticated. Run: gh auth login"
  fi
else
  echo "gh: NOT installed. See https://github.com/cli/cli#installation (Ubuntu: sudo apt install gh), then: gh auth login"
fi

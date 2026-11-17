"""MCP plugin template. Replace the example tools, keep the transport line at the bottom."""
import os

from mcp.server.mcpserver import MCPServer

NAME = os.environ.get("PLUGIN_NAME", "example-plugin")
PORT = int(os.environ.get("PORT", "8000"))

mcp = MCPServer(NAME)


@mcp.tool()
def ping() -> str:
    """Liveness probe the agent can call."""
    return "pong"


@mcp.tool()
def echo(text: str) -> str:
    """Example tool: return the input unchanged. Delete me."""
    return text


if __name__ == "__main__":
    mcp.run("streamable-http", host="0.0.0.0", port=PORT)

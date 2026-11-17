"""mcp-web-worker: drive a persistent Chromium (cookies/sessions in PROFILE_DIR) as MCP tools.

The browser is headed on Xvfb (:99). noVNC on :6080 lets a human log in once (2FA/captcha); the session then
persists in the profile volume and the agent reuses it for sites that have no API.
"""
import asyncio
import ipaddress
import os
import socket
from urllib.parse import urlparse

from mcp.server.mcpserver import MCPServer
from playwright.async_api import async_playwright

PROFILE = os.environ.get("PROFILE_DIR", "/data/profile")
NAV_TIMEOUT_MS = 30_000

mcp = MCPServer("mcp-web-worker")
_state: dict = {}
_lock = asyncio.Lock()


async def _page():
    async with _lock:
        page = _state.get("page")
        if page is None or page.is_closed():
            if "pw" not in _state:
                _state["pw"] = await async_playwright().start()
            ctx = await _state["pw"].chromium.launch_persistent_context(
                PROFILE,
                headless=False,
                args=["--no-sandbox"],  # the container is the sandbox
                viewport={"width": 1280, "height": 800},
            )
            _state["ctx"] = ctx
            _state["page"] = ctx.pages[0] if ctx.pages else await ctx.new_page()
        return _state["page"]


async def _check_url(url: str) -> None:
    """Refuse non-http(s) and non-public targets so a prompt-injected page cannot reach LiteLLM, Tailscale or metadata.

    shortcut: checks the first DNS answer only; redirects and DNS rebinding are not covered, upgrade to a
    request-interception allowlist if the agent browses untrusted sites unattended.
    """
    u = urlparse(url)
    if u.scheme not in ("http", "https") or not u.hostname:
        raise ValueError("only http(s) URLs are allowed")
    infos = await asyncio.to_thread(socket.getaddrinfo, u.hostname, None)
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if not ip.is_global:
            raise ValueError(f"blocked non-public address {ip}")


@mcp.tool()
async def open_url(url: str) -> str:
    """Navigate the persistent browser to a public http(s) URL. Returns the final URL and page title."""
    await _check_url(url)
    page = await _page()
    await page.goto(url, wait_until="domcontentloaded", timeout=NAV_TIMEOUT_MS)
    return f"{page.url} | {await page.title()}"


@mcp.tool()
async def page_text(max_chars: int = 8000) -> str:
    """Visible text of the current page, truncated to max_chars (hard cap 20000)."""
    page = await _page()
    text = await page.inner_text("body")
    return text[: min(max_chars, 20_000)]


@mcp.tool()
async def click(selector: str) -> str:
    """Click the first element matching a CSS or text selector on the current page."""
    page = await _page()
    await page.click(selector, timeout=10_000)
    return f"clicked; now at {page.url}"


@mcp.tool()
async def fill(selector: str, text: str, submit: bool = False) -> str:
    """Type text into an input; press Enter afterwards when submit is true. Never send secrets you were not given."""
    page = await _page()
    await page.fill(selector, text, timeout=10_000)
    if submit:
        await page.press(selector, "Enter")
    return f"filled; now at {page.url}"


if __name__ == "__main__":
    mcp.run("streamable-http", host="0.0.0.0", port=8001)

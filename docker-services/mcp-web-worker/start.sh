#!/usr/bin/env bash
# Start Xvfb + VNC + noVNC + the MCP server. If any of them exits, the container exits and Docker restarts it.
set -euo pipefail
: "${VNC_PASSWORD:?VNC_PASSWORD is required}"
export DISPLAY=:99

Xvfb :99 -screen 0 1280x800x24 -nolisten tcp &
for _ in $(seq 1 50); do [ -e /tmp/.X11-unix/X99 ] && break; sleep 0.1; done

x11vnc -storepasswd "$VNC_PASSWORD" /tmp/vncpass >/dev/null
x11vnc -display :99 -rfbauth /tmp/vncpass -rfbport 5900 -localhost -forever -shared -quiet &
websockify --web /usr/share/novnc 6080 127.0.0.1:5900 &
python /app/server.py &

wait -n
exit $?

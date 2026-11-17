#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu 24.04 VPS (4 vCPU / 8 GB). Idempotent: safe to re-run.
#   sudo REPO_URL=https://github.com/<owner>/<repo>.git TS_AUTHKEY=tskey-... ./deploy/setup-vps.sh
# Optional: APP_USER=hermes APP_DIR=/opt/hermes-platform BRANCH=main TS_HOSTNAME=hermes-vps CLOSE_PUBLIC_SSH=1
# It does NOT start the agent: you fill in API keys first (printed at the end).
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)" >&2; exit 1; }
: "${REPO_URL:?set REPO_URL to the git URL of this repo}"
APP_USER=${APP_USER:-hermes}
APP_DIR=${APP_DIR:-/opt/hermes-platform}
BRANCH=${BRANCH:-main}
WORKSPACE=/srv/hermes/workspace
export DEBIAN_FRONTEND=noninteractive

. /etc/os-release
[ "${VERSION_ID:-}" = "24.04" ] || echo "warn: written for Ubuntu 24.04, found ${VERSION_ID:-unknown}" >&2
as_app() { sudo -u "$APP_USER" -H "$@"; }

echo "== 1/9 packages"
apt-get update -qq
apt-get install -y -qq curl git ca-certificates jq ufw openssl util-linux nodejs npm >/dev/null

echo "== 2/9 user $APP_USER"
id "$APP_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$APP_USER"
APP_UID=$(id -u "$APP_USER"); APP_GID=$(id -g "$APP_USER"); APP_HOME=$(getent passwd "$APP_USER" | cut -d: -f6)

echo "== 3/9 docker"
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
usermod -aG docker "$APP_USER"
systemctl enable --now docker >/dev/null 2>&1

echo "== 4/9 tailscale"
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
if [ -n "${TS_AUTHKEY:-}" ]; then
  tailscale up --authkey "$TS_AUTHKEY" --ssh --hostname "${TS_HOSTNAME:-hermes-vps}"
else
  tailscale status >/dev/null 2>&1 || echo "warn: Tailscale not connected. Run: sudo tailscale up --ssh" >&2
fi

echo "== 5/9 firewall (deny inbound except Tailscale and rate-limited SSH)"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow in on tailscale0 >/dev/null
if [ "${CLOSE_PUBLIC_SSH:-0}" = 1 ]; then
  tailscale status >/dev/null 2>&1 || { echo "ERROR: refusing CLOSE_PUBLIC_SSH without a working Tailscale (you would lock yourself out)" >&2; exit 1; }
  ufw delete limit 22/tcp >/dev/null 2>&1 || true
else
  ufw limit 22/tcp >/dev/null
fi
ufw --force enable >/dev/null
# Containers publish only on 127.0.0.1 (docker-compose.yml), so Docker's iptables bypass of ufw does not expose them.

echo "== 6/9 repo + dirs"
mkdir -p "$APP_DIR" "$WORKSPACE"
chown "$APP_USER:$APP_USER" "$APP_DIR" "$WORKSPACE"
if [ ! -d "$APP_DIR/.git" ]; then
  as_app git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"   # private repo: use a read-only deploy key, not a token in the URL
fi
as_app mkdir -p "$APP_DIR/docker-services/browser-profiles"

echo "== 7/9 secrets files"
set_kv() { # set_kv FILE KEY VALUE : set only when the key is missing or empty
  local f=$1 k=$2 v=$3
  touch "$f"; chmod 600 "$f"
  if grep -q "^$k=." "$f"; then return; fi
  if grep -q "^$k=" "$f"; then sed -i "s|^$k=.*|$k=$v|" "$f"; else echo "$k=$v" >> "$f"; fi
}
ENV_FILE="$APP_DIR/.env"
[ -f "$ENV_FILE" ] || as_app cp "$APP_DIR/.env.example" "$ENV_FILE"
KEY=$(grep '^LITELLM_MASTER_KEY=.' "$ENV_FILE" | cut -d= -f2- || true)
[ -n "$KEY" ] || KEY="sk-$(openssl rand -hex 24)"
set_kv "$ENV_FILE" LITELLM_MASTER_KEY "$KEY"
set_kv "$ENV_FILE" VNC_PASSWORD "$(openssl rand -hex 8)"
set_kv "$ENV_FILE" HOST_UID "$APP_UID"; set_kv "$ENV_FILE" HOST_GID "$APP_GID"
chown "$APP_USER:$APP_USER" "$ENV_FILE"
HERMES_ENV="$APP_HOME/.hermes/.env"
as_app mkdir -p "$APP_HOME/.hermes"
set_kv "$HERMES_ENV" HERMES_CORE_DIR "$APP_DIR/hermes-core"
set_kv "$HERMES_ENV" LITELLM_MASTER_KEY "$KEY"
chown "$APP_USER:$APP_USER" "$HERMES_ENV"

echo "== 8/9 hermes (native) + gateway systemd unit"
if ! as_app bash -lc 'command -v hermes' >/dev/null 2>&1 && [ ! -x "$APP_HOME/.local/bin/hermes" ]; then
  as_app bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive'
fi
[ -x "$APP_HOME/.local/bin/uvx" ] || as_app bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'   # for the fetch MCP (uvx)
loginctl enable-linger "$APP_USER"
for _ in $(seq 1 30); do [ -S "/run/user/$APP_UID/bus" ] && break; sleep 1; done
# `hermes gateway install` writes ~/.config/systemd/user/hermes-gateway.service (documented user-service flow).
# It is installed but not started: configure messaging first with `hermes gateway setup`.
as_app env XDG_RUNTIME_DIR="/run/user/$APP_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$APP_UID/bus" \
  PATH="$APP_HOME/.local/bin:$PATH" hermes gateway install \
  || echo "warn: gateway install failed; as $APP_USER run: hermes gateway install" >&2

echo "== 9/9 GitOps timer (pull every 5 min)"
cat > /etc/systemd/system/hermes-gitops.service <<EOF
[Unit]
Description=Hermes platform GitOps sync
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=$APP_USER
Environment=XDG_RUNTIME_DIR=/run/user/$APP_UID
Environment=PATH=$APP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=REPO_DIR=$APP_DIR BRANCH=$BRANCH
ExecStart=$APP_DIR/deploy/update-vps.sh
TimeoutStartSec=900
EOF
cat > /etc/systemd/system/hermes-gitops.timer <<EOF
[Unit]
Description=Run Hermes platform GitOps sync every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now hermes-gitops.timer >/dev/null

cat <<EOF

Setup finished. Remaining manual steps (as root, then as $APP_USER):
  1. Edit $ENV_FILE: set OPENROUTER_API_KEY, CLOUDFLARE_API_KEY, CLOUDFLARE_ACCOUNT_ID (LITELLM_MASTER_KEY and VNC_PASSWORD were generated).
  2. sudo -iu $APP_USER                       # then:
     $APP_DIR/deploy/update-vps.sh --force    # applies Hermes config and starts the containers
     hermes gateway setup                     # messaging platform + allowed users
     hermes gateway start && hermes gateway status
  3. First manual web login (2FA/captcha): over Tailscale, open http://127.0.0.1:6080 through an SSH tunnel
     (ssh -L 6080:127.0.0.1:6080 $APP_USER@<tailnet-host>); VNC password is VNC_PASSWORD in $ENV_FILE.
  4. Logs: journalctl --user -u hermes-gateway -f   |   docker compose -f $APP_DIR/docker-services/docker-compose.yml logs -f
EOF

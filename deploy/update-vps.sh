#!/usr/bin/env bash
# GitOps sync, run as the app user (hermes-gitops.timer every 5 min, or by hand). Idempotent.
#   update-vps.sh            apply only what changed since the last run
#   update-vps.sh --force    re-apply everything (first run after setup-vps.sh)
#
# Session safety: Hermes is restarted only when hermes-core/config.yaml or SOUL.md changed, via
# `hermes gateway restart` (drains in-flight turns first). Containers are touched only when docker-services/ or
# mcp-plugins/ changed, and `compose up` recreates only services whose image/config changed.
set -euo pipefail

REPO_DIR=${REPO_DIR:-/opt/hermes-platform}
BRANCH=${BRANCH:-main}
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1

exec 9>/tmp/hermes-update.lock
flock -n 9 || { echo "another update is running; skipping"; exit 0; }

cd "$REPO_DIR"
dc() { docker compose --env-file "$REPO_DIR/.env" -f "$REPO_DIR/docker-services/docker-compose.yml" "$@"; }

before=$(git rev-parse HEAD)
git fetch --quiet origin "$BRANCH"
git merge --ff-only "origin/$BRANCH" >/dev/null 2>&1 \
  || { echo "ERROR: cannot fast-forward to origin/$BRANCH (local commits or conflicting files in $REPO_DIR)" >&2; exit 1; }
after=$(git rev-parse HEAD)
changed=$(git diff --name-only "$before" "$after")
want() { [ "$FORCE" = 1 ] || grep -Eq "$1" <<<"$changed"; }

if [ "$before" = "$after" ] && [ "$FORCE" = 0 ]; then
  echo "up to date at ${after:0:7}"; exit 0
fi
echo "updating ${before:0:7} -> ${after:0:7}"

# --- Hermes native: config + persona ---
if want '^hermes-core/(config\.yaml|SOUL\.md)$'; then
  mkdir -p "$HOME/.hermes"
  restart=0
  for f in config.yaml SOUL.md; do
    src="hermes-core/$f"; dst="$HOME/.hermes/$f"
    if ! cmp -s "$src" "$dst" 2>/dev/null; then
      [ -f "$dst" ] && cp "$dst" "$dst.bak"
      install -m 600 "$src" "$dst"
      restart=1
    fi
  done
  if [ "$restart" = 1 ]; then
    hermes config check || echo "warn: hermes config check reported problems (see above)" >&2
    hermes gateway restart || echo "warn: gateway restart failed; is the service installed? (hermes gateway install)" >&2
  fi
fi

# --- Docker services ---
if want '^(docker-services|mcp-plugins)/'; then
  dc config -q   # validate before touching anything that is running
  dc up -d --build --remove-orphans --wait --wait-timeout 180 \
    || { echo "ERROR: services unhealthy after update" >&2; dc ps >&2; dc logs --tail 30 >&2; exit 1; }
  docker image prune -f >/dev/null
fi

echo "done: ${after:0:7}"

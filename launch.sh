#!/usr/bin/env bash
set -euo pipefail

# ── Paths ──────────────────────────────────────────────
REPO_DIR="$HOME/Dev/openclaw"
DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Pull latest ────────────────────────────────────────
echo "==> Pulling latest OpenClaw source"
if ! git -C "$REPO_DIR" pull --ff-only; then
  echo "    ⚠ git pull failed (merge conflict?). Continuing with current source."
fi

# ── Preflight checks ──────────────────────────────────
if [[ ! -f "$DATA_DIR/openclaw.json" ]]; then
  echo "Error: openclaw.json not found. Copy the example and fill in your details:"
  echo "  cp $DATA_DIR/openclaw.json.example $DATA_DIR/openclaw.json"
  exit 1
fi

# ── Config ─────────────────────────────────────────────
export OPENCLAW_CONFIG_DIR="$DATA_DIR"
export OPENCLAW_WORKSPACE_DIR="$DATA_DIR/workspace"
export OPENCLAW_HOME_VOLUME=openclaw-home
export OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$(python3 -c "import json,sys; print(json.load(open('$DATA_DIR/openclaw.json'))['gateway']['auth']['token'])" 2>/dev/null || echo "")}"

cd "$REPO_DIR"

# ── Build base image ──────────────────────────────────
echo ""
echo "==> Building base image"
if docker build -t openclaw:local -f "$REPO_DIR/Dockerfile" "$REPO_DIR"; then
  echo "    ✓ Base image built successfully"
  BASE_BUILT=true
else
  echo "    ⚠ Base image build failed."
  if docker image inspect openclaw:local >/dev/null 2>&1; then
    echo "    Using previous openclaw:local image."
    BASE_BUILT=false
  else
    echo "    ✗ No previous image found. Cannot continue."
    exit 1
  fi
fi

# ── Build tools layer ─────────────────────────────────
echo ""
echo "==> Building tools layer (brew, Claude Code, Kimi CLI, OpenCode, gh)"
SCRIPTS_HASH=$(cat "$DATA_DIR"/scripts/*.sh 2>/dev/null | shasum | cut -c1-8)
if docker build --build-arg SCRIPTS_HASH="$SCRIPTS_HASH" -t openclaw:tools -f "$DATA_DIR/Dockerfile.tools" "$DATA_DIR"; then
  echo "    ✓ Tools image built successfully"
else
  echo "    ⚠ Tools image build failed."
  if docker image inspect openclaw:tools >/dev/null 2>&1; then
    echo "    Using previous openclaw:tools image."
  else
    echo "    ✗ No previous image found. Cannot continue."
    exit 1
  fi
fi

# ── Write .env for docker-compose ──────────────────────
# Source existing .env to preserve generated values (e.g. GOG_KEYRING_PASSWORD)
if [[ -f "$REPO_DIR/.env" ]]; then
  set +u; source "$REPO_DIR/.env"; set -u
fi
cat > "$REPO_DIR/.env" <<EOF
OPENCLAW_CONFIG_DIR=$DATA_DIR
OPENCLAW_WORKSPACE_DIR=$DATA_DIR/workspace
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_BRIDGE_PORT=18790
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN
OPENCLAW_IMAGE=openclaw:tools
OPENCLAW_EXTRA_MOUNTS=
OPENCLAW_HOME_VOLUME=openclaw-home
OPENCLAW_DOCKER_APT_PACKAGES=
GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD:-$(openssl rand -hex 16)}
EOF

# ── Start / restart gateway ────────────────────────────
echo ""
echo "==> Starting gateway"
docker compose -f "$REPO_DIR/docker-compose.yml" -f "$DATA_DIR/docker-compose.extra.yml" up -d openclaw-gateway

echo ""
echo "==========================================="
echo " OpenClaw is running!"
echo "==========================================="
echo ""
echo " Dashboard: http://localhost:18789/chat?session=main&token=$OPENCLAW_GATEWAY_TOKEN"
echo " Logs:      docker compose -f $REPO_DIR/docker-compose.yml -f $DATA_DIR/docker-compose.extra.yml logs -f openclaw-gateway"
echo " Shell:     docker compose -f $REPO_DIR/docker-compose.yml -f $DATA_DIR/docker-compose.extra.yml exec openclaw-gateway bash"
echo ""
if [[ "${BASE_BUILT:-true}" == false ]]; then
  echo " ⚠ Note: running on a previous base image. Check upstream for build fixes."
  echo ""
fi
echo " To configure coding tools, open a shell and run:"
echo "   claude login"
echo "   kimi auth login"
echo "   opencode auth login"
echo "   gog auth add you@gmail.com --services user --manual"
echo ""

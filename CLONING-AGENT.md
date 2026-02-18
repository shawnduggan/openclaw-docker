# Cloning an OpenClaw Agent Instance

This guide walks through creating a second OpenClaw agent (e.g. a QA agent) alongside your existing Coder agent. Each agent gets its own config, Telegram bot, ports, and data — but they share the same Docker images.

## Overview

```
~/openclaw-docker/        ← Coder agent (port 18789)
~/openclaw-docker-qa/     ← QA agent (port 18791)
~/Dev/openclaw/           ← Shared repo (one copy)
```

## Step 1: Create the data directory

```bash
mkdir -p ~/openclaw-docker-qa/workspace
mkdir -p ~/openclaw-docker-qa/agents/main/agent
mkdir -p ~/openclaw-docker-qa/.gog
```

## Step 2: Create a Telegram bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. `/newbot` → give it a name (e.g. "QA Agent") and username
3. Copy the bot token (you'll need it for `openclaw.json`)

## Step 3: Create openclaw.json

Copy and modify from the coder agent:

```bash
cp ~/openclaw-docker/openclaw.json ~/openclaw-docker-qa/openclaw.json
```

Edit `~/openclaw-docker-qa/openclaw.json` and change:

- **`gateway.port`** → `18791`
- **`gateway.auth.token`** → generate a new one: `openssl rand -hex 16`
- **`channels.telegram.botToken`** → your new bot's token
- **`channels.telegram.groups`** → update group IDs if needed
- **Agent config** (`agents.defaults.model`, `agents.list`, etc.) → tailor for QA role
- **`tools.elevated.allowFrom.telegram`** → your Telegram user ID (same as coder if it's you)

## Step 4: Copy auth profiles

If the QA agent uses the same API keys (kimi-coding, google, etc.):

```bash
cp ~/openclaw-docker/agents/main/agent/auth-profiles.json \
   ~/openclaw-docker-qa/agents/main/agent/auth-profiles.json
```

## Step 5: Create docker-compose.qa.yml

Create `~/openclaw-docker-qa/docker-compose.qa.yml`:

```yaml
services:
  openclaw-gateway-qa:
    image: openclaw:tools
    container_name: openclaw-qa-gateway
    environment:
      HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN}
      GOG_KEYRING_PASSWORD: ${GOG_KEYRING_PASSWORD}
    volumes:
      - openclaw-home-qa:/home/node
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
      - ${OPENCLAW_CONFIG_DIR}/.gog:/home/node/.config/gogcli
    ports:
      - "${OPENCLAW_GATEWAY_PORT:-18791}:18791"
      - "${OPENCLAW_BRIDGE_PORT:-18792}:18792"
    init: true
    restart: unless-stopped
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "lan",
        "--port",
        "18791",
      ]

volumes:
  openclaw-home-qa:
```

## Step 6: Create launch.sh

Create `~/openclaw-docker-qa/launch.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$HOME/Dev/openclaw"
DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$DATA_DIR/docker-compose.qa.yml"

# Pull latest and rebuild images (shared with coder agent)
echo "==> Pulling latest OpenClaw source"
if ! git -C "$REPO_DIR" pull --ff-only; then
  echo "    ⚠ git pull failed (merge conflict?). Continuing with current source."
fi

echo "==> Building base image"
if docker build -t openclaw:local -f "$REPO_DIR/Dockerfile" "$REPO_DIR"; then
  echo "    ✓ Base image built successfully"
else
  echo "    ⚠ Base image build failed."
  if docker image inspect openclaw:local >/dev/null 2>&1; then
    echo "    Using previous openclaw:local image."
  else
    echo "    ✗ No previous image found. Cannot continue."
    exit 1
  fi
fi

echo "==> Building tools layer"
# Reuse the same Dockerfile.tools from the coder agent
if docker build -t openclaw:tools -f "$HOME/openclaw-docker/Dockerfile.tools" "$HOME/openclaw-docker"; then
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

# Write .env for docker-compose
# Source existing .env to preserve generated values (e.g. GOG_KEYRING_PASSWORD)
if [[ -f "$DATA_DIR/.env" ]]; then
  set +u; source "$DATA_DIR/.env"; set -u
fi
cat > "$DATA_DIR/.env" <<EOF
OPENCLAW_CONFIG_DIR=$DATA_DIR
OPENCLAW_WORKSPACE_DIR=$DATA_DIR/workspace
OPENCLAW_GATEWAY_PORT=18791
OPENCLAW_BRIDGE_PORT=18792
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-$(openssl rand -hex 16)}
GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD:-$(openssl rand -hex 16)}
EOF

echo "==> Starting QA gateway"
docker compose -f "$COMPOSE_FILE" up -d openclaw-gateway-qa

OPENCLAW_GATEWAY_TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN "$DATA_DIR/.env" | cut -d= -f2)

echo ""
echo "==========================================="
echo " QA Agent is running!"
echo "==========================================="
echo ""
echo " Dashboard: http://localhost:18791/chat?session=main&token=$OPENCLAW_GATEWAY_TOKEN"
echo " Logs:      docker compose -f $COMPOSE_FILE logs -f openclaw-gateway-qa"
echo " Shell:     docker compose -f $COMPOSE_FILE exec openclaw-gateway-qa bash"
echo ""
```

```bash
chmod +x ~/openclaw-docker-qa/launch.sh
```

The first run auto-generates `OPENCLAW_GATEWAY_TOKEN` and `GOG_KEYRING_PASSWORD` and saves them to `.env`. Subsequent runs reuse the same values.

## Step 7: First run

```bash
~/openclaw-docker-qa/launch.sh
```

Then pair Telegram (message your new QA bot, and approve):

```bash
docker compose -f ~/openclaw-docker-qa/docker-compose.qa.yml exec openclaw-gateway-qa \
  node dist/index.js pairing approve telegram <CODE>
```

Configure coding tools if needed:

```bash
docker compose -f ~/openclaw-docker-qa/docker-compose.qa.yml exec openclaw-gateway-qa bash
# then: claude login, kimi auth login, opencode auth login
```

## Port allocation

Keep a simple convention to avoid conflicts:

| Agent  | Gateway port | Bridge port |
|--------|-------------|-------------|
| Coder  | 18789       | 18790       |
| QA     | 18791       | 18792       |
| Agent3 | 18793       | 18794       |

## Tips

- **Shared images**: All agents use the same `openclaw:local` and `openclaw:tools` images. Only one rebuild needed.
- **Independent data**: Each agent has its own config, sessions, workspace, and Telegram bot. They don't interfere.
- **Independent home volumes**: Tool logins (Claude, Kimi, OpenCode) are per-agent via separate Docker volumes.
- **GOG tokens per agent**: Each agent has its own `.gog/` directory bind-mounted for persistent Google auth.
- **Separate compose files**: Each agent has its own compose file, so `docker compose up/down` only affects that agent.
- **Shared workspace**: If you want agents to collaborate on the same code, point both `OPENCLAW_WORKSPACE_DIR` to the same host directory. Otherwise keep them separate.

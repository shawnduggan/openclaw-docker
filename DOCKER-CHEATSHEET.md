# OpenClaw Docker Cheatsheet

All commands assume you're on your Mac. The repo lives at `~/Dev/openclaw`.

## How the two compose files work

`launch.sh` starts the container using **both** compose files:

```bash
docker compose -f ~/Dev/openclaw/docker-compose.yml -f ~/openclaw-docker/docker-compose.extra.yml up -d
```

The base `docker-compose.yml` defines the services. The extra file adds host bind mounts (`.gog/`, etc.) and env vars. Both files are only needed when **creating or recreating** the container.

For day-to-day commands that operate on an **already-running** container (`stop`, `start`, `restart`, `exec`, `logs`, `ps`), you only need the base file — these commands just target the container by name, they don't need the full config.

**When to use `launch.sh`:**
- First start, after pulling new code, rebuilding images, or changing compose/env config

**When the short commands are fine:**
- Stopping, starting, restarting, shelling in, viewing logs on an existing container

## Update & Rebuild

```bash
~/openclaw-docker/launch.sh
```

Pulls latest, rebuilds both images, restarts the gateway. If a build fails, it falls back to the previous working image. You only need this when code or config changes — not for routine stop/start.

## Shell Access

```bash
# Interactive shell (as the node user)
docker compose -f ~/Dev/openclaw/docker-compose.yml exec openclaw-gateway bash

# Run a single openclaw command without entering a shell
docker compose -f ~/Dev/openclaw/docker-compose.yml exec openclaw-gateway openclaw <command>

# Shell as root (for installing packages, debugging)
docker compose -f ~/Dev/openclaw/docker-compose.yml exec -u root openclaw-gateway bash
```

## OpenClaw Commands (inside the container shell)

The `openclaw` command works inside the container just like on a VM:

```bash
openclaw status            # Check gateway status
openclaw doctor            # Diagnose issues
openclaw security audit    # Security check
openclaw devices list      # List paired devices
openclaw config get        # View config values
openclaw skills list       # List installed skills
openclaw skills check      # Check skill requirements
openclaw cron list         # List cron jobs
```

## Logs

```bash
# Follow gateway logs (Ctrl+C to stop)
docker compose -f ~/Dev/openclaw/docker-compose.yml logs -f openclaw-gateway

# Last 50 lines
docker compose -f ~/Dev/openclaw/docker-compose.yml logs --tail 50 openclaw-gateway
```

## Start / Stop / Restart

These work on an already-created container. No need to reference the extra compose file.

```bash
# Stop the gateway
docker compose -f ~/Dev/openclaw/docker-compose.yml stop openclaw-gateway

# Start it again (keeps existing container with all mounts intact)
docker compose -f ~/Dev/openclaw/docker-compose.yml start openclaw-gateway

# Restart
docker compose -f ~/Dev/openclaw/docker-compose.yml restart openclaw-gateway

# Stop and remove the container entirely (next start requires launch.sh)
docker compose -f ~/Dev/openclaw/docker-compose.yml down
```

## Dashboard

Open in browser:

```
http://localhost:18789/chat?session=main&token=<YOUR_GATEWAY_TOKEN>
```

## Coding Tools (inside the container shell)

```bash
claude login          # Authenticate Claude Code
kimi auth login       # Authenticate Kimi CLI
opencode auth login   # Authenticate OpenCode
gh auth login         # Authenticate GitHub CLI
```

These logins persist across rebuilds (stored in the `openclaw-home` Docker volume).

### Google Workspace (gogcli)

gogcli (`gog`) provides Gmail, Calendar, Drive, Contacts, and more from the CLI. Since the container can't open a browser, use `--manual` mode:

```bash
gog auth add you@gmail.com --services user --manual
```

1. The CLI prints an authorization URL
2. Copy it and open in a browser on your Mac
3. Complete the Google OAuth flow
4. Copy the redirect URL from your browser's address bar and paste it back into the container terminal

Verify it worked:

```bash
gog calendar list     # List upcoming calendar events
gog mail list         # List recent emails
```

Tokens are stored in `~/.config/gogcli/` (bind-mounted from `~/openclaw-docker/.gog/` on your Mac — survives container rebuilds and volume prunes).

## Installing Skills

Skills can be installed from inside the container shell. Most use `brew` or `npm`, both of which are available:

```bash
openclaw skills list       # See available skills
openclaw skills check      # Check what's installed vs missing
```

Installed skills are stored in `~/openclaw-docker/skills/` on your Mac, so they persist across rebuilds.

## Telegram Pairing

If Telegram says "pairing required" after a rebuild:

```bash
docker compose -f ~/Dev/openclaw/docker-compose.yml exec openclaw-gateway \
  openclaw pairing approve telegram <CODE>
```

Replace `<CODE>` with the pairing code shown in the Telegram message.

## Directory Structure

### On your Mac (`~/openclaw-docker/`)

```
~/openclaw-docker/
├── openclaw.json          # Main config (gateway, channels, agents, API keys)
├── launch.sh              # One-command update/rebuild/restart
├── Dockerfile.tools       # Tools layer (Claude Code, Kimi CLI, OpenCode, gh, qmd, brew)
├── agents/                # Agent data (auth profiles, session history)
│   └── main/
│       ├── agent/
│       │   ├── auth-profiles.json   # API keys for providers
│       │   └── models.json
│       └── qmd/               # QMD memory search index (auto-created)
│           ├── xdg-config/
│           └── xdg-cache/
├── cron/                  # Cron job definitions
│   └── jobs.json
├── credentials/           # Channel credentials (Telegram allowlists)
├── completions/           # Completion cache
├── devices/               # Paired device records
│   ├── paired.json
│   └── pending.json
├── identity/              # Bot identity data
├── memory/                # Agent memory databases
│   ├── main.sqlite
│   └── coder.sqlite
├── scripts/               # Custom scripts
├── subagents/             # Subagent data
├── telegram/              # Telegram-specific state
├── canvas/                # Control UI static files
├── workspace/             # Main agent workspace (code, docs, tasks)
├── workspace-coder/       # Coder-specific workspace
├── workspace-main/        # Main-specific workspace
├── .claude/               # Claude-specific config from VM
├── exec-approvals.json    # Exec approval records
├── update-check.json      # Update check timestamp
├── DOCKER-CHEATSHEET.md   # This file
├── CLONING-AGENT.md       # Guide: creating additional agents
└── CLOUD-DEPLOYMENT.md    # Guide: deploying to AWS/cloud
```

### Inside the container

| Container path | Maps to | What |
|---|---|---|
| `/home/node/.openclaw/` | `~/openclaw-docker/` | Config + all state data |
| `/home/node/.openclaw/workspace/` | `~/openclaw-docker/workspace/` | Agent workspace |
| `/home/node/.config/gogcli/` | `~/openclaw-docker/.gog/` | GOG CLI auth tokens |
| `/home/node/` | Docker volume `openclaw-home` | Tool configs (claude, gh, kimi) |

### What lives where

| Data | Location | Persists across rebuilds? |
|---|---|---|
| OpenClaw config | `~/openclaw-docker/openclaw.json` | Yes (your Mac) |
| API keys | `~/openclaw-docker/agents/main/agent/auth-profiles.json` | Yes (your Mac) |
| Cron jobs | `~/openclaw-docker/cron/jobs.json` | Yes (your Mac) |
| Agent workspace/code | `~/openclaw-docker/workspace/` | Yes (your Mac) |
| Installed skills | `~/openclaw-docker/skills/` | Yes (your Mac) |
| QMD memory index | `~/openclaw-docker/agents/main/qmd/` | Yes (your Mac) |
| GOG CLI auth tokens | `~/openclaw-docker/.gog/` | Yes (your Mac) |
| Tool logins (claude, gh) | Docker volume `openclaw-home` | Yes (Docker volume) |
| Brew-installed packages | Inside container image | No (rebuilt each time) |
| npm global packages | Inside container image | No (rebuilt each time) |

## Docker Housekeeping

```bash
# See running containers
docker ps

# Disk usage
docker system df

# Clean up old images (reclaim space)
docker image prune

# Nuclear option — remove all unused images, volumes, etc.
# ⚠ WARNING: This deletes the openclaw-home volume (tool logins)!
docker system prune -a --volumes
```

## Memory Search (QMD)

QMD is the local memory search backend. It indexes markdown files and session transcripts for semantic recall.

```bash
# Check QMD status (inside the container shell)
qmd --version

# Manually trigger an index update
XDG_CONFIG_HOME=/home/node/.openclaw/agents/main/qmd/xdg-config \
XDG_CACHE_HOME=/home/node/.openclaw/agents/main/qmd/xdg-cache \
qmd update

# Run embeddings
XDG_CONFIG_HOME=/home/node/.openclaw/agents/main/qmd/xdg-config \
XDG_CACHE_HOME=/home/node/.openclaw/agents/main/qmd/xdg-cache \
qmd embed
```

The gateway manages QMD automatically (updates every 5 min, embeds every 60 min). First search may be slow as QMD downloads local GGUF models.

Config in `openclaw.json` under `memory`:
```json
"memory": {
  "backend": "qmd",
  "qmd": {
    "includeDefaultMemory": true,
    "sessions": { "enabled": true },
    "update": { "interval": "5m" }
  }
}
```

## Troubleshooting

### HTTPS / web_fetch not working

Node.js in the container can't find CA certificates by default. The Dockerfile.tools sets `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt` to fix this. If HTTPS fetches fail but `curl` works, check that this env var is set:

```bash
docker compose -f ~/Dev/openclaw/docker-compose.yml exec openclaw-gateway printenv NODE_EXTRA_CA_CERTS
# Should print: /etc/ssl/certs/ca-certificates.crt
```

```bash
# Is the container running?
docker ps | grep openclaw

# Check container resource usage
docker stats openclaw-openclaw-gateway-1

# Inspect the container config
docker inspect openclaw-openclaw-gateway-1

# Check if the gateway responds
curl http://localhost:18789
```

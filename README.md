# OpenClaw Docker Setup

A batteries-included Docker companion for [OpenClaw](https://github.com/openclaw/openclaw). Adds a tools layer, resilient update workflow, and comprehensive documentation for running OpenClaw in Docker on a Mac.

## What's Included

- **`Dockerfile.tools`** — Extends the base OpenClaw image with Claude Code, Kimi CLI, OpenCode, GitHub CLI, QMD (memory search), and Homebrew
- **`launch.sh`** — One-command update: pulls latest source, rebuilds both images, restarts the gateway. Falls back to previous images if a build fails
- **`openclaw.json.example`** — Sanitized config template with all the knobs documented
- **`cron/jobs.json`** — Cron job definitions (morning briefs, research reports, journaling, maintenance)
- **`DOCKER-CHEATSHEET.md`** — Quick reference for common Docker commands, directory structure, and troubleshooting
- **`CLONING-AGENT.md`** — Step-by-step guide for creating additional agent instances
- **`CLOUD-DEPLOYMENT.md`** — Deploying to AWS, DigitalOcean, Hetzner, Railway, and more

## Prerequisites

- **Docker Desktop** (Mac) or **Docker Engine** (Linux) — with Compose v2
- **Git**

## Quick Start

```bash
# 1. Clone the OpenClaw source
git clone https://github.com/openclaw/openclaw.git ~/Dev/openclaw

# 2. Clone this repo (anywhere you like)
git clone https://github.com/shawnduggan/openclaw-docker.git ~/openclaw-docker

# 3. Copy the example files and fill in your details
cp ~/openclaw-docker/openclaw.json.example ~/openclaw-docker/openclaw.json
cp ~/openclaw-docker/cron/jobs.json.example ~/openclaw-docker/cron/jobs.json

# 4. Edit openclaw.json — add your API keys, Telegram bot token, and user IDs
# 5. Edit cron/jobs.json — customize job schedules, messages, and delivery targets

# 6. Build and start
~/openclaw-docker/launch.sh
```

The dashboard URL (with auth token) is printed when launch finishes.

### Path configuration

`launch.sh` expects the OpenClaw source repo at `~/Dev/openclaw`. If yours is elsewhere, edit `REPO_DIR` at the top of `launch.sh`. The config directory (`DATA_DIR`) is auto-detected from wherever you cloned this repo.

## Update Workflow

After the initial setup, updating is one command:

```bash
~/openclaw-docker/launch.sh
```

This pulls the latest OpenClaw source, rebuilds both Docker images (base + tools), writes the `.env` file, and restarts the gateway. If a build fails, it falls back to the previous working image.

## Tools in the Container

| Tool | Install method | Purpose |
|---|---|---|
| Claude Code | Native installer | AI coding assistant |
| OpenCode | npm | AI coding assistant |
| Kimi CLI | uv (Python >=3.12) | AI coding assistant |
| GitHub CLI | apt (official repo) | Git operations |
| QMD | npm | Local memory search with BM25 + vectors |
| gogcli | Binary | Google Workspace CLI (Gmail, Calendar, Drive) |
| Homebrew | Linuxbrew | Package manager for skill dependencies |

Tool logins persist across rebuilds via a Docker volume.

## Problems This Solves

- **HTTPS not working in container** — Node.js can't find CA certificates; fixed with `NODE_EXTRA_CA_CERTS`
- **Gateway unreachable through Docker** — Bind config trick: `loopback` in config (for internal pairing), `lan` override in docker-compose (for port mapping)
- **QMD module resolution** — Must use `npm install -g` not `bun install -g` (bun's flat layout breaks node's resolver)
- **Kimi CLI Python version** — Requires >=3.12 but base image has 3.11; solved with `uv` to a shared prefix
- **Homebrew as root** — Brew refuses to run as root; installed as `node` user with passwordless sudo
- **Build failures** — `launch.sh` gracefully falls back to previous images instead of leaving you broken

## Example Files

Files containing secrets or personal details are gitignored. The repo ships `.example` versions instead:

| Example file | Copy to | What to customize |
|---|---|---|
| `openclaw.json.example` | `openclaw.json` | API keys, Telegram bot token, user IDs, group IDs |
| `cron/jobs.json.example` | `cron/jobs.json` | Job schedules, messages, Telegram delivery targets |

Your real config files are never tracked by git.

## Directory Structure

See [DOCKER-CHEATSHEET.md](DOCKER-CHEATSHEET.md) for the full directory layout, volume mapping, and persistence details.

## License

This is a personal setup repo. Feel free to use it as a reference or starting point for your own OpenClaw Docker configuration.

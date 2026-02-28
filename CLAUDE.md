# OpenClaw Docker Setup

This repo contains the Docker customization layer for running OpenClaw on a Mac. The OpenClaw source repo lives at `~/Dev/openclaw` — this repo holds config, tooling, and docs that sit outside it.

## Architecture

- **Base image** (`openclaw:local`): built from `~/Dev/openclaw/Dockerfile`
- **Tools image** (`openclaw:tools`): built from `Dockerfile.tools` here, extends base with Claude Code, Kimi CLI, OpenCode, gh, qmd, mcporter, Homebrew
- **Config**: `openclaw.json` (gitignored — contains secrets). Use `openclaw.json.example` as a template.
- **Update workflow**: `./launch.sh` — pulls latest source, rebuilds both images, restarts gateway

## Key files

| File | Purpose |
|---|---|
| `Dockerfile.tools` | Tools layer added on top of base OpenClaw image |
| `launch.sh` | One-command update/rebuild/restart (resilient to build failures) |
| `docker-compose.extra.yml` | Extra volumes and env vars layered on top of base compose |
| `openclaw.json` | Main config (SECRETS — gitignored) |
| `openclaw.json.example` | Sanitized config template (safe to commit) |
| `cron/jobs.json` | Cron job definitions |
| `.gog/` | GOG CLI auth tokens (bind-mounted, gitignored) |
| `DOCKER-CHEATSHEET.md` | Common Docker commands and directory structure |
| `CLONING-AGENT.md` | Guide for creating additional agent instances |
| `CLOUD-DEPLOYMENT.md` | Guide for deploying to cloud providers |
| `mcporter.json` | mcporter config — registers qmd as a keep-alive MCP server |

## Docker commands

```bash
# Rebuild and restart
./launch.sh

# Shell into container
docker compose -f ~/Dev/openclaw/docker-compose.yml exec openclaw-gateway bash

# View logs
docker compose -f ~/Dev/openclaw/docker-compose.yml logs -f openclaw-gateway
```

## Config philosophy

`openclaw.json` should **only contain fields that differ from upstream defaults**. Do not restate default values — it creates drift surface and hides intentional choices among noise.

- **Include**: API keys, secrets, model choices, agent definitions, opt-in features (`memory.qmd.mcporter.enabled`), values you've deliberately overridden
- **Omit**: Timeouts, limits, search modes, rate limits, or anything that matches what upstream would use anyway
- When upstream improves a default, you get the improvement automatically
- Every line in the config should be a deliberate choice

To check if a value is a default, look at `~/Dev/openclaw/src/config/defaults.ts`, the relevant `backend-config.ts`, or `zod-schema.*.ts` files.

## Important conventions

- **Never commit `openclaw.json`** — it contains API keys and tokens
- If you change the config structure, update `openclaw.json.example` too
- Container runs as `node` user — tools installed as root must be accessible to `node`
- Container paths use `/home/node/.openclaw/` (not host paths like `/Users/shawn/`)
- The `.env` file lives in `~/Dev/openclaw/` and is written by `launch.sh`
- Gateway bind is `"loopback"` in config but overridden to `lan` by docker-compose for port mapping

## Gotchas

- Kimi CLI needs Python >=3.12; installed via `uv` to `/opt/uv-tools/` (shared location)
- qmd and mcporter installed via `npm install -g` (not bun — bun's module resolution breaks node)
- mcporter config lives at `/etc/mcporter/mcporter.json` (not `~/.mcporter/`) because `/home/node` is a volume mount; `MCPORTER_CONFIG` env var points to it
- `NODE_EXTRA_CA_CERTS` must be set for HTTPS to work in the container
- Homebrew must be installed as non-root user (brew refuses root)
- If base image build fails, `launch.sh` falls back to previous image
- GOG CLI tokens are bind-mounted from `.gog/` → `/home/node/.config/gogcli/` (not the named volume) so they survive `docker volume prune`
- GOG credentials.json must use Google's `{"installed": {...}}` wrapper format
- `node_modules/.bin/` from macOS lacks +x on Linux — npm/pnpm wrappers auto-fix permissions before every command
- Workspace projects may use pnpm (`node_modules/.pnpm/` exists) — use `pnpm install`, not `npm install`, or npm will destroy the pnpm layout. `npm run` commands work fine either way.

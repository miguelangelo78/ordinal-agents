# ordinal-agents

This file provides guidance to Claude Code when working with code in this repository.

## What This Is

ordinal-agents is a Docker-based AI agent system. A single privileged "god container" runs Docker-in-Docker, Claude Code Web, and cc-bridge. Open WebUI is the primary chat interface. The main agent can spawn isolated subagent containers inside its DinD environment.

## Build & Run

```bash
# Local dev
cp .env.example .env   # Set ANTHROPIC_API_KEY
docker compose build
docker compose up -d    # Main agent on localhost:AGENT_BASE_PORT (default 3000)

# VPS (with Caddy + Authelia)
docker compose --profile vps up -d

# Tear down (keeps volumes)
docker compose down
```

## Subagent Management (inside god container)

```bash
./agents.sh spawn <id> [--role "description"]   # id: 1-20
./agents.sh stop <id>
./agents.sh rm <id>
./agents.sh list
./agents.sh logs <id>
```

## Architecture

- God container: `--privileged` for DinD, runs supervisord (dockerd, cc-web, cc-bridge)
- Open WebUI: Chat interface on port 3080 (local) / main domain (VPS). Connects to cc-bridge.
- Subagents: `--network host` inside DinD (bind ports in god container's namespace)
- Port scheme: `AGENT_BASE_PORT` + id. Main = base, subagent N = base+N. Max 20.
- cc-bridge: OpenAI-compatible API on port 4000 (internal). Wraps Claude Agent SDK — Open WebUI gets full Claude Code capabilities.
- VPS: Caddy (wildcard subdomain TLS via DNS challenge) + Authelia (2FA, sessions)

## Key Files

- `Dockerfile` — God container image
- `supervisord.conf` — Process management (dockerd, cc-web, cc-bridge)
- `cc-bridge/` — OpenAI-compatible bridge wrapping Claude Agent SDK
- `entrypoint.sh` — Container init (volume sync + supervisord)
- `agents.sh` — Subagent CLI
- `agent/CLAUDE.md` — Main agent personality
- `subagents/template/` — Subagent image template
- `caddy/Caddyfile` — Reverse proxy with static entries for all 20 subagent subdomains
- `authelia/configuration.yml` — Auth config

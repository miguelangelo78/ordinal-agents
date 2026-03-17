# ordinal-agents

A single powerful AI agent running in a Docker container, accessible remotely from anywhere. The agent has full control of its own machine (container) and can spawn sub-containers via Docker-in-Docker.

## Prerequisites

- Docker + Docker Compose
- An [Anthropic API key](https://console.anthropic.com/)
- (VPS only) A domain with wildcard DNS and Cloudflare API token

## Quick Start (Local Dev)

```bash
cp .env.example .env
# Edit .env: set ANTHROPIC_API_KEY

docker compose build
docker compose up -d
```

Open **http://localhost:3080** for the chat interface (Open WebUI).
CC Web terminal is still available at **http://localhost:3000**.

## VPS Deployment

### 1. DNS Setup

Create these DNS records pointing to your VPS IP:

| Record | Type | Value |
|--------|------|-------|
| `agent.yourdomain.com` | A | VPS IP |
| `*.agent.yourdomain.com` | A | VPS IP |

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env`:
- `ANTHROPIC_API_KEY` — your Anthropic API key
- `AGENT_BASE_PORT` — base port (default 3000)
- `AGENT_BASE_PORT_END` — must equal AGENT_BASE_PORT + 20
- `CC_WEB_AUTH` — Claude Code Web access token
- `AGENT_DOMAIN` — your domain (e.g., `agent.yourdomain.com`)
- `DNS_PROVIDER` — `cloudflare` (for TLS cert DNS challenge)
- `DNS_API_TOKEN` — Cloudflare API token with DNS edit permissions
- `AUTHELIA_JWT_SECRET` — random string for JWT signing
- `AUTHELIA_SESSION_SECRET` — random string for session encryption
- `AUTHELIA_STORAGE_ENCRYPTION_KEY` — random string for storage encryption
- `AGENT_BASE_PORT_1` through `AGENT_BASE_PORT_20` — update if you changed AGENT_BASE_PORT

### 3. Set Authelia Password

Generate a password hash:

```bash
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'YOUR_PASSWORD'
```

Edit `authelia/users.yml` and replace the placeholder hash.

### 4. Start

```bash
docker compose --profile vps up -d
```

Access:
- **https://agent.yourdomain.com** — Open WebUI (chat)
- **https://cc.agent.yourdomain.com** — Claude Code Web (terminal/files)
- **https://auth.agent.yourdomain.com** — Authelia login
- **https://s1.agent.yourdomain.com** through **s20** — Subagent bridges

## Subagent Management

From inside the god container (or via Claude Code Web terminal):

```bash
# Spawn a subagent with a role
./agents.sh spawn 1 --role "You are a frontend developer specializing in React."

# List running subagents
./agents.sh list

# View subagent logs
./agents.sh logs 1

# Stop a subagent (keeps data)
./agents.sh stop 1

# Remove a subagent and all its data
./agents.sh rm 1
```

Each subagent gets:
- Its own cc-bridge instance on port `AGENT_BASE_PORT + id`
- An isolated workspace volume
- A custom `CLAUDE.md` defining its role

Max 20 subagents (IDs 1-20).

## Architecture

```
Host Machine
├── Open WebUI (chat interface on port 3080)
│   └─ connects to → cc-bridge inside god container
└── God Container (--privileged, DinD)
    ├── supervisord
    │   ├── dockerd (Docker-in-Docker daemon)
    │   ├── cc-web (Claude Code Web on AGENT_BASE_PORT)
    │   └── cc-bridge (Claude Code SDK bridge on port 4000)
    └── DinD containers (--network host)
        ├── subagent-1 (cc-bridge on AGENT_BASE_PORT+1)
        ├── subagent-2 (cc-bridge on AGENT_BASE_PORT+2)
        └── ...

VPS only:
├── Caddy (TLS via DNS challenge, wildcard subdomains)
└── Authelia (2FA authentication, session cookies)
```

## Port Scheme

| Service | Port |
|---------|------|
| Main agent | `AGENT_BASE_PORT` (default 3000) |
| Open WebUI | `OPEN_WEBUI_PORT` (default 3080) |
| Subagent N | `AGENT_BASE_PORT + N` |
| cc-bridge | 4000 (internal only) |

Ports bind to `127.0.0.1`. On VPS, Caddy proxies external traffic via wildcard subdomains on port 443.

## Security Model

- The god container runs with `--privileged` (required for DinD). No host Docker socket is mounted — the container is the sandbox.
- On VPS: Caddy provides TLS, Authelia provides authentication (username/password + optional TOTP 2FA) with configurable session duration.
- Claude Code Web has its own auth token (`CC_WEB_AUTH`) as a secondary gate.
- Subagents are isolated: each has its own container, workspace volume, and config volume.


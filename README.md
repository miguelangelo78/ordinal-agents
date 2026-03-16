# ordinal-agents

Numbered AI agents in Docker. **You manage other agents by talking to agent-0 in Claude Code** — say "spawn agent 1", "stop agent 2", "list agents", and agent-0 runs the commands. Agent 0 is always the orchestrator (repo + Docker socket); agents 1, 2, … are isolated and only agent-0 can create or stop them.

## How it works

```
ordinal-agents/
├── Dockerfile.base        # Shared base: Node 22, Python, tmux, Claude Code CLI
├── docker-compose.yml     # Agent-0 only (bridge runs inside it)
├── agents.sh              # Build, up/down, spawn, despawn, enter, web, status
├── bridge/                # HTTP bridge (bundled in agent-0; started by entrypoint)
├── 0/
│   ├── Dockerfile         # Extends base + Docker CLI (so 0 can run docker)
│   └── CLAUDE.md          # 0's identity: orchestrator, builder, trader
└── 1/, 2/, ...            # Created when you ask 0 to spawn an agent
```

- **Talk to agent-0 in the browser** at http://localhost:32350/?token=agent0. Say "spawn agent 1", "ask agent 1 what 2+2 is", etc. The **bridge** runs inside agent-0 (no separate service to start), so agent-0 can message other agents and get replies.
- **Agent 0** gets a **copy** of the repo in its workspace (the host repo is mounted read-only and copied in on first run). So agent-0 never modifies your real files. It has the Docker socket and the integrated bridge.
- **Agents 1, 2, …** run in separate containers with named volumes. They can't see each other or the host. You (or agent-0 when you ask) create `<id>/CLAUDE.md` and `<id>/Dockerfile`, then agent-0 runs `./agents.sh spawn <id>`.

```
node:22-bookworm
  └── agent-base           (shared tooling)
        ├── agent-0        (orchestrator: Docker CLI, socket, repo as workspace)
        └── agent-1, ...   (spawned by 0 or host; isolated)
```

## Prerequisites

- A Linux server (Debian/Ubuntu) with Docker installed
- An Anthropic API key from [console.anthropic.com](https://console.anthropic.com)

## Setup

```bash
git clone https://github.com/miguelangelo78/ordinal-agents.git
cd ordinal-agents
chmod +x agents.sh

# Build and start agent 0 (orchestrator). No shell commands after this.
./agents.sh build 0
./agents.sh up 0
./agents.sh key 0 sk-ant-api03-YOUR-KEY
```

**Open http://localhost:32350/?token=agent0 in your browser.** The default access token is `agent0`; set `CC_WEB_AUTH` (env or in `.env` with Compose) to use a custom token. Talk to agent-0 there — e.g. "spawn agent 1", "stop agent 2", "list agents".

## Docker Compose (VPS / agent-0 only)

Compose runs **agent-0 only**. The container starts the bridge and Web UI automatically (nothing to start manually). Open the URL and talk to agent-0.

```bash
cp .env.example .env
# Edit .env: ANTHROPIC_API_KEY=sk-ant-api03-...

docker compose build agent-base
docker compose build agent-0
docker compose up -d agent-0
```

**Open http://localhost:32350/?token=agent0** (or `http://<vps-ip>:32350/?token=agent0` on a VPS). Default token is `agent0`; set `CC_WEB_AUTH` in `.env` for a custom token. Restrict port 32350 with a firewall or reverse proxy if the VPS is public.

To stop agent-0 but keep login and config for next time, use **`docker compose down`** (do not use `-v`, or volumes and login will be removed).

## Script port binding (agents.sh)

By default `./agents.sh up 0` binds the Web UI port to **127.0.0.1** (localhost only). To expose the port on the VPS so you can open `http://<vps-ip>:32350`:

```bash
export ORDINAL_AGENTS_BIND=0.0.0.0
./agents.sh up 0
```

Or one-shot: `ORDINAL_AGENTS_BIND=0.0.0.0 ./agents.sh up 0`. Use a firewall or reverse proxy if the VPS is public.

## Commands

| Command | Description |
|---|---|
| `./agents.sh build [id]` | Build base image + agent image |
| `./agents.sh up [id]` | Start agent (0 = Web UI auto-starts; open browser) |
| `./agents.sh spawn [id]` | Build + up for id 1, 2, … (ask agent-0 in the browser or run from host) |
| `./agents.sh despawn [id]` | Stop agent 1, 2, … |
| `./agents.sh enter [id]` | Launch Claude Code inside agent |
| `./agents.sh web [id]` | Launch Claude Code Web UI |
| `./agents.sh shell [id]` | Open bash shell inside agent |
| `./agents.sh down [id]` | Stop + remove container (data preserved) |
| `./agents.sh nuke [id]` | Remove container AND all data |
| `./agents.sh key [id] [key]` | Set Anthropic API key |
| `./agents.sh status` | Show all agent containers and volumes |

## Workspace isolation

Each agent uses **its own** workspace and config volumes: `agent-0-workspace`, `agent-1-workspace`, … and `agent-0-config`, `agent-1-config`, … (Compose may prefix names, e.g. `ordinal-agents_agent-0-workspace`). No agent shares another’s workspace.

To verify, run `./agents.sh status`: it prints which volume is mounted as workspace and config per container. Each row should show a different volume name per agent.

## Shell aliases

Add to your `~/.bashrc` for quick access:

```bash
alias 0="cd ~/ordinal-agents && ./agents.sh enter 0"
alias 0sh="cd ~/ordinal-agents && ./agents.sh shell 0"
alias 1="cd ~/ordinal-agents && ./agents.sh enter 1"
alias 1sh="cd ~/ordinal-agents && ./agents.sh shell 1"
```

Then from any SSH session: `0` drops you into Claude Code, `0sh` gives you the container's bash shell.

## Adding a new agent (1, 2, …)

Create the agent dir and files (or ask agent-0 in Claude Code to create them):

```bash
mkdir 2
```

Add `2/CLAUDE.md` (personality) and `2/Dockerfile`:

```dockerfile
FROM agent-base:latest

COPY --chown=claude:claude CLAUDE.md /home/claude/workspace/CLAUDE.md

RUN git config --global user.name "2" && \
    git config --global user.email "2@sandbox" && \
    git config --global init.defaultBranch main
```

Then **tell agent-0 in Claude Code** e.g. "spawn agent 2" — it will run `./agents.sh spawn 2`. To attach: "open a shell for agent 2" or run `./agents.sh enter 2` from the host. To stop: ask agent-0 to despawn 2, or `./agents.sh despawn 2`. Set API key: `./agents.sh key 2 sk-ant-api03-YOUR-KEY` (or use the shared `key` file when starting).

## Security model

- **Agent 0** has the Docker socket and the repo bind-mounted so it can orchestrate. It is a trusted context; only start it when you control the host.
- **Agents 1, 2, …** use named volumes only; no bind mounts, no socket. Isolated from each other and the host.
- **No `--privileged`** — containers have no elevated permissions.
- **No `--network host`** — containers use Docker's default bridge network.
- **Non-root user** — Claude Code runs as user `claude` inside the container.
- `--dangerously-skip-permissions` is safe for agent containers because the container **is** the sandbox.

## License

MIT
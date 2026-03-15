# ordinal-agents

Numbered AI agents running in isolated Docker containers. Each agent gets its own personality, workspace, and identity — managed by a single script.

## How it works

```
ordinal-agents/
├── Dockerfile.base        # Shared base: Node 22, Python, tmux, Claude Code CLI
├── agents.sh              # One script to manage all agents
├── 0/
│   ├── Dockerfile         # Extends base, injects 0's personality
│   └── CLAUDE.md          # 0's identity: builder, trader, coworker
└── 1/
    ├── Dockerfile         # Extends base, ready for 1's identity
    └── CLAUDE.md          # Placeholder — define when ready
```

Each agent runs as a separate Docker container with named volumes. They can't see each other, can't reach the host machine. Everything an agent builds — apps, databases, files — lives and dies inside its own container.

```
node:22-bookworm
  └── agent-base           (shared tooling layer)
        ├── agent-0        (0's personality + git identity)
        └── agent-1        (1's personality + git identity)
```

## Prerequisites

- A Linux server (Debian/Ubuntu) with Docker installed
- An Anthropic API key from [console.anthropic.com](https://console.anthropic.com)

## Setup

```bash
git clone https://github.com/miguelangelo78/ordinal-agents.git
cd ordinal-agents
chmod +x agents.sh

# Build and start agent 0
./agents.sh build 0
./agents.sh up 0
./agents.sh key 0 sk-ant-api03-YOUR-KEY

# Talk to 0
./agents.sh enter 0
```

## Commands

| Command | Description |
|---|---|
| `./agents.sh build [id]` | Build base image + agent image |
| `./agents.sh up [id]` | Start agent container |
| `./agents.sh enter [id]` | Launch Claude Code inside agent |
| `./agents.sh shell [id]` | Open bash shell inside agent |
| `./agents.sh down [id]` | Stop + remove container (data preserved) |
| `./agents.sh nuke [id]` | Remove container AND all data |
| `./agents.sh key [id] [key]` | Set Anthropic API key |
| `./agents.sh status` | Show all running agents |

## Shell aliases

Add to your `~/.bashrc` for quick access:

```bash
alias 0="cd ~/ordinal-agents && ./agents.sh enter 0"
alias 0sh="cd ~/ordinal-agents && ./agents.sh shell 0"
alias 1="cd ~/ordinal-agents && ./agents.sh enter 1"
alias 1sh="cd ~/ordinal-agents && ./agents.sh shell 1"
```

Then from any SSH session: `0` drops you into Claude Code, `0sh` gives you the container's bash shell.

## Adding a new agent

```bash
mkdir 2
```

Create `2/CLAUDE.md` with the agent's personality, and `2/Dockerfile`:

```dockerfile
FROM agent-base:latest

COPY --chown=claude:claude CLAUDE.md /home/claude/workspace/CLAUDE.md

RUN git config --global user.name "2" && \
    git config --global user.email "2@sandbox" && \
    git config --global init.defaultBranch main
```

Then:

```bash
./agents.sh build 2
./agents.sh up 2
./agents.sh key 2 sk-ant-api03-YOUR-KEY
./agents.sh enter 2
```

## Security model

- **Named volumes only** — no bind mounts to the host filesystem
- **No `--privileged`** — containers have no elevated permissions
- **No `--network host`** — containers use Docker's default bridge network
- **Non-root user** — Claude Code runs as user `claude` inside the container
- `--dangerously-skip-permissions` is safe here because the Docker container **is** the sandbox

## License

MIT
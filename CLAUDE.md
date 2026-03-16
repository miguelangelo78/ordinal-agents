# ordinal-agents

Numbered AI agents (0, 1, 2, …) in Docker. **You manage other agents by talking to agent-0 in Claude Code** — e.g. "spawn agent 1", "stop agent 2", "list agents". Agent-0 runs the corresponding `./agents.sh` commands. Agent 0 is the orchestrator (repo + Docker socket); agents 1, 2, … are isolated and only agent-0 can create/stop them.

## Layout

- **`Dockerfile.base`** — Shared image: Node 22, Python, git, tmux, Claude Code CLI + Web. User `claude`, workdir `/home/claude/workspace`.
- **`agents.sh`** — Build, up/down, enter/shell/web, **spawn** (build+up for id ≥ 1), **despawn** (down for id ≥ 1), key, status. Agent 0 gets Docker socket + repo bind mount when started with `up 0` or Compose.
- **`docker-compose.yml`** — Agent-0 only. Repo is mounted read-only at /repo-src; workspace is a volume. Entrypoint copies repo → workspace on first run so agent-0 never touches the host repo.
- **`bridge/`** — HTTP service in agent-0 image; entrypoint starts it so agent-0 can message other agents.
- **`0/`** — Dockerfile (Docker CLI + bridge), entrypoint (copy repo into workspace, then bridge + Web UI), CLAUDE.md.
- **`<id>/`** (id ≥ 1) — Per-agent dir: `Dockerfile` (FROM agent-base, copy `CLAUDE.md`, git identity) and `CLAUDE.md`. Created by you or by asking agent-0; then ask agent-0 to spawn (it runs `./agents.sh spawn <id>`).

## Running

- **Start orchestrator (script or Compose):** build and start agent-0 (e.g. `./agents.sh up 0` or `docker compose up -d agent-0`). The Web UI starts automatically. **Open http://localhost:32350** — no shell commands. Talk to agent-0 there to spawn/despawn/list agents; it runs `./agents.sh` in the terminal.
- API key: repo `key` file or `./agents.sh key 0 <key>`; Compose uses `.env`.

## Adding an agent (id ≥ 1)

Create `<id>/CLAUDE.md` and `<id>/Dockerfile` (see README), then ask agent-0 in Claude Code to spawn that agent (it runs `./agents.sh spawn <id>`). To remove: ask agent-0 to despawn it, or run `./agents.sh despawn <id>` / `down` / `nuke` from the host.

## Conventions

- Agent 0 is the only one with Docker socket and repo mount; it orchestrates. Others use named volumes only.
- Base port 32350; agent `id` uses port `32350 + id`.

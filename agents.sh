#!/bin/bash
# agents.sh — manage agents 0, 1, 2, ...
# Usage:
#   ./agents.sh build [id]     Build base + agent image
#   ./agents.sh up [id]        Start agent container
#   ./agents.sh enter [id]     Launch Claude Code (CLI)
#   ./agents.sh web [id]       Launch Claude Code (Web UI)
#   ./agents.sh shell [id]     Open a bash shell inside agent
#   ./agents.sh down [id]      Stop and remove container (keeps data)
#   ./agents.sh nuke [id]      Remove container AND volumes (full reset)
#   ./agents.sh spawn [id]     Build + up (id >= 1; from host or inside agent-0)
#   ./agents.sh despawn [id]   Down (id >= 1)
#   ./agents.sh status         Show all agent containers (alias: list)
#   ./agents.sh key [id] [key] Set API key for an agent
# Agent 0 is the orchestrator: gets Docker socket + repo mount so it can spawn/despawn others.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-help}"
AGENT_ID="${2}"

BASE_PORT=32350   # agent 0 = 32350, agent 1 = 32351, ...
# Bind port on host: 127.0.0.1 (localhost only) or 0.0.0.0 (all interfaces, for VPS access)
BIND_ADDRESS="${ORDINAL_AGENTS_BIND:-127.0.0.1}"

container_name() { echo "agent-${1}"; }
image_name() { echo "agent-${1}"; }
# Each agent gets a unique workspace and config volume (no sharing)
workspace_vol() { echo "agent-${1}-workspace"; }
config_vol() { echo "agent-${1}-config"; }
agent_port() { echo $(( BASE_PORT + ${1} )); }

build_base() {
    echo "=== Building base image ==="
    docker build -t agent-base -f "${SCRIPT_DIR}/Dockerfile.base" "${SCRIPT_DIR}"
}

build_agent() {
    local id="$1"
    local dir="${SCRIPT_DIR}/${id}"

    if [ ! -d "$dir" ]; then
        echo "Error: No agent directory at ${dir}"
        exit 1
    fi

    build_base
    echo "=== Building agent ${id} ==="
    if [ "$id" = "0" ]; then
        # Agent 0: build from repo root so image gets full repo at /home/claude/workspace
        docker build -t "$(image_name "$id")" -f "${dir}/Dockerfile" "${SCRIPT_DIR}"
    else
        docker build -t "$(image_name "$id")" -f "${dir}/Dockerfile" "${dir}"
    fi
}

up_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    local port="$(agent_port "$id")"

    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "Container ${name} already exists. Use 'enter' to attach or 'down' first."
        exit 1
    fi

    # Load API key from key file
    local key_file="${SCRIPT_DIR}/key"
    local key_flag=""
    if [ -f "$key_file" ]; then
        local api_key
        api_key="$(cat "$key_file" | tr -d '[:space:]')"
        key_flag="-e ANTHROPIC_API_KEY=${api_key}"
        echo "Using API key from ${key_file}"
    else
        echo "Warning: No key file found at ${key_file}. Set it later with: ./agents.sh key ${id} YOUR-KEY"
    fi

    local vol_workspace vol_extra web_auth_flag bridge_flag
    if [ "$id" = "0" ]; then
        # Agent 0: repo is read-only at /repo-src; workspace is a volume (entrypoint copies repo -> workspace so 0 never touches originals)
        vol_workspace="-v ${SCRIPT_DIR}:/repo-src:ro -v $(workspace_vol "$id"):/home/claude/workspace"
        vol_extra="-v /var/run/docker.sock:/var/run/docker.sock -v agent-0-config-dotconfig:/home/claude/.config"
        web_auth_flag="-e CC_WEB_AUTH=${CC_WEB_AUTH:-agent0}"
        bridge_flag="-e BRIDGE_URL=http://localhost:32360"
    else
        vol_workspace="-v $(workspace_vol "$id"):/home/claude/workspace"
        vol_extra=""
        web_auth_flag=""
        bridge_flag=""
    fi

    # Agent 0: no command = entrypoint starts bridge + Web UI
    local run_cmd="sleep infinity"
    [ "$id" = "0" ] && run_cmd=""

    echo "=== Starting agent ${id} (port ${port}) ==="
    docker run -d \
        --name "${name}" \
        --hostname "${name}" \
        ${key_flag} \
        ${web_auth_flag} \
        ${bridge_flag} \
        -p "${BIND_ADDRESS}:${port}:${port}" \
        ${vol_workspace} \
        -v "$(config_vol "$id"):/home/claude/.claude" \
        ${vol_extra} \
        --restart unless-stopped \
        "$(image_name "$id")" \
        ${run_cmd}

    # Fix volume permissions. Agent 0: entrypoint does .claude; only fix for id >= 1
    if [ "$id" != "0" ]; then
        docker exec -u root "${name}" chown -R claude:claude /home/claude/.claude /home/claude/workspace
    fi

    echo ""
    echo "Agent ${id} is alive."
    echo "  Workspace volume: $(workspace_vol "$id")"
    echo "  Config volume:   $(config_vol "$id")"
    if [ "$id" = "0" ]; then
        echo "  Open in browser:  http://localhost:${port}/?token=${CC_WEB_AUTH:-agent0}"
        echo "  CLI (optional):   ./agents.sh enter ${id}"
    else
        echo "  CLI:    ./agents.sh enter ${id}"
        echo "  Web UI: ./agents.sh web ${id}"
    fi
    echo "  Shell:  ./agents.sh shell ${id}"
    echo "  Key:    ./agents.sh key ${id} sk-ant-api03-YOUR-KEY"
}

enter_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    # Agent 0: repo is at /home/claude/workspace; start Claude Code there so agents.sh is visible at ./
    if [ "$id" = "0" ]; then
        docker exec -it "${name}" bash -lc "cd /home/claude/workspace && claude --dangerously-skip-permissions"
    else
        docker exec -it "${name}" bash -lc "claude --dangerously-skip-permissions"
    fi
}

web_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    local port="$(agent_port "$id")"

    echo "=== Starting Web UI for agent ${id} on port ${port} ==="
    echo ""
    echo "Access from this machine:  http://localhost:${port}"
    echo "Access via SSH tunnel:     ssh -L ${port}:localhost:${port} user@your-vps"
    echo "  then open:               http://localhost:${port}"
    echo ""
    echo "Press Ctrl+C to stop the Web UI (agent keeps running)"
    echo ""

    # Agent 0: start Web UI with repo as cwd so workspace is ordinal-agents (agents.sh at ./)
    if [ "$id" = "0" ]; then
        docker exec -it "${name}" bash -lc "cd /home/claude/workspace && cc-web --no-open --port ${port}"
    else
        docker exec -it "${name}" bash -lc "cc-web --no-open --port ${port}"
    fi
}

shell_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    docker exec -it "${name}" bash -l
}

down_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    echo "=== Stopping agent ${id} ==="
    docker rm -f "${name}" 2>/dev/null || true
    echo "Container removed. Volumes preserved."
}

nuke_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    echo "=== Nuking agent ${id} (container + volumes) ==="
    docker rm -f "${name}" 2>/dev/null || true
    docker volume rm "$(workspace_vol "$id")" 2>/dev/null || true
    docker volume rm "$(config_vol "$id")" 2>/dev/null || true
    [ "$id" = "0" ] && docker volume rm agent-0-config-dotconfig 2>/dev/null || true
    echo "Agent ${id} fully removed."
}

set_key() {
    local id="$1"
    local key="$2"
    local name="$(container_name "$id")"

    if [ -z "$key" ]; then
        echo "Usage: ./agents.sh key ${id} sk-ant-api03-YOUR-KEY"
        exit 1
    fi

    docker exec "${name}" bash -c "
        sed -i '/ANTHROPIC_API_KEY/d' ~/.bashrc
        echo 'export ANTHROPIC_API_KEY=${key}' >> ~/.bashrc
    "
    echo "API key set for agent ${id}."
}

show_status() {
    echo "=== Agent Containers ==="
    docker ps -a --filter "name=agent-" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
    echo ""
    echo "=== Workspace/Config per container (verify no sharing) ==="
    for name in $(docker ps -a --filter "name=agent-" --format "{{.Names}}" | sort -V); do
        echo "  ${name}:"
        docker inspect "${name}" --format '{{range .Mounts}}{{if eq .Destination "/home/claude/workspace"}}    workspace <- {{.Name}}{{println}}{{end}}{{if eq .Destination "/home/claude/.claude"}}    .claude   <- {{.Name}}{{println}}{{end}}{{end}}' 2>/dev/null || true
    done
    echo ""
    echo "=== Agent Volumes ==="
    docker volume ls --filter "name=agent-" --format "table {{.Name}}\t{{.Driver}}"
}

spawn_agent() {
    local id="$1"
    if [ "$id" = "0" ]; then
        echo "Use ./agents.sh up 0 to start agent 0. Spawn is for additional agents (1, 2, ...)."
        exit 1
    fi
    build_agent "$id"
    up_agent "$id"
}

despawn_agent() {
    local id="$1"
    if [ "$id" = "0" ]; then
        echo "Use ./agents.sh down 0 to stop agent 0. Despawn is for additional agents (1, 2, ...)."
        exit 1
    fi
    down_agent "$id"
}

case "$CMD" in
    build)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh build [id]" && exit 1
        build_agent "$AGENT_ID"
        ;;
    up)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh up [id]" && exit 1
        up_agent "$AGENT_ID"
        ;;
    spawn)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh spawn [id]  (id >= 1)" && exit 1
        spawn_agent "$AGENT_ID"
        ;;
    despawn)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh despawn [id]  (id >= 1)" && exit 1
        despawn_agent "$AGENT_ID"
        ;;
    enter)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh enter [id]" && exit 1
        enter_agent "$AGENT_ID"
        ;;
    web)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh web [id]" && exit 1
        web_agent "$AGENT_ID"
        ;;
    shell)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh shell [id]" && exit 1
        shell_agent "$AGENT_ID"
        ;;
    down)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh down [id]" && exit 1
        down_agent "$AGENT_ID"
        ;;
    nuke)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh nuke [id]" && exit 1
        nuke_agent "$AGENT_ID"
        ;;
    key)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh key [id] [api-key]" && exit 1
        set_key "$AGENT_ID" "$3"
        ;;
    status|list)
        show_status
        ;;
    *)
        echo "agents.sh — agent 0 orchestrates; others are spawned/despawned by 0 or from host"
        echo ""
        echo "Usage:"
        echo "  ./agents.sh build [id]          Build base + agent image"
        echo "  ./agents.sh up [id]             Start agent (0 = with Docker socket + repo)"
        echo "  ./agents.sh spawn [id]          Build + up for id 1, 2, ... (from host or agent-0)"
        echo "  ./agents.sh despawn [id]        Stop agent 1, 2, ..."
        echo "  ./agents.sh enter [id]          Launch Claude Code (CLI)"
        echo "  ./agents.sh web [id]            Launch Claude Code (Web UI)"
        echo "  ./agents.sh shell [id]          Open bash shell inside agent"
        echo "  ./agents.sh down [id]           Stop container (keeps data)"
        echo "  ./agents.sh nuke [id]           Remove container + all data"
        echo "  ./agents.sh key [id] [api-key]  Set Anthropic API key"
        echo "  ./agents.sh status              Show all agents"
        echo ""
        echo "Examples:"
        echo "  ./agents.sh up 0                # Start orchestrator (agent 0)"
        echo "  ./agents.sh enter 0             # CLI; then inside 0: ./agents.sh spawn 1"
        echo "  ./agents.sh spawn 1             # From host: build and start agent 1"
        echo "  ./agents.sh key 0 sk-ant-api03-xxxxx"
        ;;
esac
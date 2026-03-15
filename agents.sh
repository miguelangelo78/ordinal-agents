#!/bin/bash
# agents.sh — manage agents 0, 1, 2, ...
# Usage:
#   ./agents.sh build [id]     Build base + agent image
#   ./agents.sh up [id]        Start agent container
#   ./agents.sh enter [id]     Launch Claude Code inside agent
#   ./agents.sh shell [id]     Open a bash shell inside agent
#   ./agents.sh down [id]      Stop and remove container (keeps data)
#   ./agents.sh nuke [id]      Remove container AND volumes (full reset)
#   ./agents.sh status         Show all agent containers
#   ./agents.sh key [id] [key] Set API key for an agent

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-help}"
AGENT_ID="${2}"

container_name() { echo "agent-${1}"; }
image_name() { echo "agent-${1}"; }
workspace_vol() { echo "agent-${1}-workspace"; }
config_vol() { echo "agent-${1}-config"; }

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
    docker build -t "$(image_name "$id")" -f "${dir}/Dockerfile" "${dir}"
}

up_agent() {
    local id="$1"
    local name="$(container_name "$id")"

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

    echo "=== Starting agent ${id} ==="
    docker run -d \
        --name "${name}" \
        --hostname "${name}" \
        ${key_flag} \
        -v "$(workspace_vol "$id"):/home/claude/workspace" \
        -v "$(config_vol "$id"):/home/claude/.claude" \
        --restart unless-stopped \
        "$(image_name "$id")" \
        sleep infinity

    # Fix volume permissions (Docker creates them as root)
    docker exec -u root "${name}" chown -R claude:claude /home/claude/.claude /home/claude/workspace

    echo "Agent ${id} is alive."
    echo "  Claude Code: ./agents.sh enter ${id}"
    echo "  Bash shell:  ./agents.sh shell ${id}"
    echo "  Set key:     ./agents.sh key ${id} sk-ant-api03-YOUR-KEY"
}

enter_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    docker exec -it "${name}" bash -lc "claude --dangerously-skip-permissions"
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
    docker ps -a --filter "name=agent-" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    echo ""
    echo "=== Agent Volumes ==="
    docker volume ls --filter "name=agent-" --format "table {{.Name}}\t{{.Driver}}"
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
    enter)
        [ -z "$AGENT_ID" ] && echo "Usage: ./agents.sh enter [id]" && exit 1
        enter_agent "$AGENT_ID"
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
    status)
        show_status
        ;;
    *)
        echo "agents.sh — manage sandboxed Claude Code agents"
        echo ""
        echo "Usage:"
        echo "  ./agents.sh build [id]          Build base + agent image"
        echo "  ./agents.sh up [id]             Start agent container"
        echo "  ./agents.sh enter [id]          Launch Claude Code inside agent"
        echo "  ./agents.sh shell [id]          Open bash shell inside agent"
        echo "  ./agents.sh down [id]           Stop container (keeps data)"
        echo "  ./agents.sh nuke [id]           Remove container + all data"
        echo "  ./agents.sh key [id] [api-key]  Set Anthropic API key"
        echo "  ./agents.sh status              Show all agents"
        echo ""
        echo "Examples:"
        echo "  ./agents.sh build 0"
        echo "  ./agents.sh up 0"
        echo "  ./agents.sh enter 0"
        echo "  ./agents.sh key 0 sk-ant-api03-xxxxx"
        ;;
esac
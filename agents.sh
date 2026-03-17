#!/bin/bash
# agents.sh — subagent management inside the god container
# Run from /home/claude/workspace inside the god container.
#
# Usage:
#   ./agents.sh spawn <id> [--role "description"]
#   ./agents.sh stop <id>
#   ./agents.sh rm <id>
#   ./agents.sh list
#   ./agents.sh logs <id>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-help}"
AGENT_ID="${2}"

BASE_PORT="${AGENT_BASE_PORT:-3000}"
MAX_AGENTS=20

container_name() { echo "subagent-${1}"; }
agent_port() { echo $(( BASE_PORT + ${1} )); }
workspace_vol() { echo "subagent-${1}-workspace"; }
config_vol() { echo "subagent-${1}-config"; }

ensure_base_image() {
    if ! docker image inspect subagent-base:latest >/dev/null 2>&1; then
        echo "=== Building subagent base image ==="
        local build_ctx=$(mktemp -d)
        cp -r "${SCRIPT_DIR}/subagents/template/"* "${build_ctx}/"
        cp -r "${SCRIPT_DIR}/cc-bridge/" "${build_ctx}/cc-bridge/"
        docker build -t subagent-base:latest -f "${build_ctx}/Dockerfile.base" "${build_ctx}"
        rm -rf "${build_ctx}"
    fi
}

validate_id() {
    local id="$1"
    if [ -z "$id" ]; then
        echo "Error: agent ID required" >&2
        exit 1
    fi
    if ! [[ "$id" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: agent ID must be a positive integer (1-${MAX_AGENTS})" >&2
        exit 1
    fi
    if [ "$id" -gt "$MAX_AGENTS" ]; then
        echo "Error: max ${MAX_AGENTS} subagents (port range limit)" >&2
        exit 1
    fi
}

spawn_agent() {
    local id="$1"
    shift
    local role=""

    # Parse --role flag
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --role)
                if [ -z "${2:-}" ]; then
                    echo "Error: --role requires a value" >&2
                    exit 1
                fi
                role="$2"; shift 2 ;;
            *) echo "Warning: unknown option '$1'" >&2; shift ;;
        esac
    done

    local name="$(container_name "$id")"
    local port="$(agent_port "$id")"

    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "Subagent ${id} already exists. Use 'stop' first or 'rm' to remove."
        exit 1
    fi

    ensure_base_image

    # Create subagent CLAUDE.md
    local claude_md="${SCRIPT_DIR}/subagents/${id}"
    mkdir -p "$claude_md"

    if [ -n "$role" ]; then
        cat > "${claude_md}/CLAUDE.md" <<MDEOF
# Subagent ${id}

${role}
MDEOF
    elif [ ! -f "${claude_md}/CLAUDE.md" ]; then
        cp "${SCRIPT_DIR}/subagents/template/CLAUDE.md" "${claude_md}/CLAUDE.md"
    fi

    # Build subagent image with its CLAUDE.md
    echo "=== Building subagent ${id} ==="
    docker build -t "subagent-${id}:latest" \
        -f "${SCRIPT_DIR}/subagents/template/Dockerfile" \
        "${claude_md}"

    echo "=== Starting subagent ${id} on port ${port} ==="
    docker run -d \
        --name "${name}" \
        --hostname "${name}" \
        --network host \
        -e AGENT_PORT="${port}" \
        -e AGENT_MODEL="${name}" \
        -v "$(workspace_vol "$id"):/home/claude/workspace" \
        -v "$(config_vol "$id"):/home/claude/.claude" \
        --restart unless-stopped \
        "subagent-${id}:latest"

    echo ""
    echo "Subagent ${id} running on port ${port}"
    echo "  Container: ${name}"
    echo "  Workspace: $(workspace_vol "$id")"
}

stop_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    echo "=== Stopping subagent ${id} ==="
    docker stop "${name}" 2>/dev/null || true
    docker rm "${name}" 2>/dev/null || true
    echo "Subagent ${id} stopped."
}

rm_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    echo "=== Removing subagent ${id} (container + volumes) ==="
    docker rm -f "${name}" 2>/dev/null || true
    docker volume rm "$(workspace_vol "$id")" 2>/dev/null || true
    docker volume rm "$(config_vol "$id")" 2>/dev/null || true
    rm -rf "${SCRIPT_DIR}/subagents/${id}"

    echo "Subagent ${id} fully removed."
}

list_agents() {
    echo "=== Subagents ==="
    docker ps -a --filter "name=subagent-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

logs_agent() {
    local id="$1"
    local name="$(container_name "$id")"
    docker logs -f "${name}"
}

case "$CMD" in
    spawn)
        validate_id "$AGENT_ID"
        shift 2
        spawn_agent "$AGENT_ID" "$@"
        ;;
    stop)
        validate_id "$AGENT_ID"
        stop_agent "$AGENT_ID"
        ;;
    rm)
        validate_id "$AGENT_ID"
        rm_agent "$AGENT_ID"
        ;;
    list)
        list_agents
        ;;
    logs)
        validate_id "$AGENT_ID"
        logs_agent "$AGENT_ID"
        ;;
    *)
        echo "agents.sh — subagent management"
        echo ""
        echo "Usage:"
        echo "  ./agents.sh spawn <id> [--role \"description\"]"
        echo "  ./agents.sh stop <id>"
        echo "  ./agents.sh rm <id>"
        echo "  ./agents.sh list"
        echo "  ./agents.sh logs <id>"
        echo ""
        echo "Agent IDs: 1-${MAX_AGENTS} (port = BASE_PORT + id)"
        ;;
esac

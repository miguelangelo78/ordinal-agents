#!/bin/bash
set -e

# Ensure log directory exists
mkdir -p /var/log/supervisor

# Fix ownership of mounted volumes
chown -R claude:claude /home/claude/workspace /home/claude/.claude 2>/dev/null || true

# Sync staged files into workspace (survives volume mounts)
cp -f /opt/ordinal-agents/agents.sh /home/claude/workspace/agents.sh
cp -f /opt/ordinal-agents/CLAUDE.md /home/claude/workspace/CLAUDE.md
cp -rf /opt/ordinal-agents/subagents/ /home/claude/workspace/subagents/
cp -rf /opt/ordinal-agents/cc-bridge/ /home/claude/workspace/cc-bridge/
chown -R claude:claude /home/claude/workspace

# Start supervisord (manages dockerd, cc-web, cc-bridge)
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf

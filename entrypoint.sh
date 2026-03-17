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

# Restore .claude.json from backup if missing (not on a volume, lost on redeploy)
if [ ! -f /home/claude/.claude.json ] && [ -d /home/claude/.claude/backups ]; then
    LATEST_BACKUP=$(ls -t /home/claude/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
        cp "$LATEST_BACKUP" /home/claude/.claude.json
        chown claude:claude /home/claude/.claude.json
        echo "Restored .claude.json from backup"
    fi
fi

# Create startup banner to remind agent to read memory
if [ -f /home/claude/workspace/.startup-banner.sh ]; then
    su -p claude -c "bash /home/claude/workspace/.startup-banner.sh" || true
fi

# Display agent memory on startup (if exists)
if [ -f /home/claude/workspace/.load-memory.sh ]; then
    echo ""
    echo "==============================================="
    echo "🚨 AUTO-LOADING AGENT MEMORY ON STARTUP 🚨"
    echo "==============================================="
    su -p claude -c "bash /home/claude/workspace/.load-memory.sh" || true
    echo ""
fi

# Start supervisord (manages dockerd, cc-web, cc-bridge)
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf

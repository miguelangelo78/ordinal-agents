#!/bin/sh
# Run as root: copy repo into workspace (so agent-0 never touches the host repo), then bridge + Web UI.
# /repo-src is the host repo (read-only). /home/claude/workspace is a volume — we copy into it on first run.
if [ -d /repo-src ] && [ ! -f /home/claude/workspace/agents.sh ]; then
    cp -a /repo-src/. /home/claude/workspace/
    chown -R claude:claude /home/claude/workspace
fi
# So the Web UI loads "You are 0" — overwrite root CLAUDE.md with agent-0's identity
cp /home/claude/workspace/0/CLAUDE.md /home/claude/workspace/CLAUDE.md
chown claude:claude /home/claude/workspace/CLAUDE.md
chown -R claude:claude /home/claude/.claude /home/claude/.config 2>/dev/null || true

# Bridge in background (reads from workspace copy)
REPO_PATH=/home/claude/workspace node /app/bridge/server.js &

TOKEN="${CC_WEB_AUTH:-agent0}"
exec su -s /bin/bash claude -c "cd /home/claude/workspace && exec cc-web --no-open --port 32350 --auth \"$TOKEN\""

FROM subagent-base:latest

COPY CLAUDE.md /opt/CLAUDE.md

RUN printf '#!/bin/bash\nset -e\nchown -R claude:claude /home/claude/workspace /home/claude/.claude 2>/dev/null || true\ncp -f /opt/CLAUDE.md /home/claude/workspace/CLAUDE.md\nchown claude:claude /home/claude/workspace/CLAUDE.md\nPORT="${AGENT_PORT:-3001}"\nMODEL="${AGENT_MODEL:-subagent}"\nexec su -p claude -s /bin/bash -c "BRIDGE_PORT=$PORT BRIDGE_MODEL=$MODEL BRIDGE_CWD=/home/claude/workspace exec node /opt/cc-bridge/index.js"\n' > /entrypoint.sh \
    && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

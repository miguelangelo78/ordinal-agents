FROM debian:bookworm-slim

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# System packages + supervisord
RUN apt-get update && apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    git tmux wget jq unzip \
    python3 python3-pip python3-venv \
    build-essential sudo \
    supervisor \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Docker CE (for DinD)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
       https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI + Web UI
RUN npm install -g @anthropic-ai/claude-code claude-code-web

# cc-bridge (OpenAI-compatible SDK wrapper)
COPY cc-bridge/ /opt/cc-bridge/
RUN cd /opt/cc-bridge && npm install --production

# Non-root user with sudo + docker group
RUN useradd -m -s /bin/bash claude \
    && usermod -aG sudo,docker claude \
    && echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Workspace and config dirs
RUN mkdir -p /home/claude/workspace /home/claude/.claude \
    && chown -R claude:claude /home/claude

# Defaults for supervisord env var references
ENV AGENT_BASE_PORT=3000
ENV CC_WEB_AUTH=agent0

# Copy config files
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY entrypoint.sh /entrypoint.sh
# Stage files for entrypoint sync (volumes mask direct COPY to workspace)
COPY agent/CLAUDE.md /opt/ordinal-agents/CLAUDE.md
COPY agents.sh /opt/ordinal-agents/agents.sh
COPY subagents/ /opt/ordinal-agents/subagents/
COPY cc-bridge/ /opt/ordinal-agents/cc-bridge/

RUN chmod +x /entrypoint.sh /opt/ordinal-agents/agents.sh \
    && chown -R claude:claude /home/claude

# Git config for main agent
RUN su - claude -c "git config --global user.name 'agent' && \
    git config --global user.email 'agent@sandbox' && \
    git config --global init.defaultBranch main"

WORKDIR /home/claude/workspace

ENTRYPOINT ["/entrypoint.sh"]

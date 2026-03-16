# Build with context = repo root:  docker build -f 0/Dockerfile .
FROM agent-base:latest

USER root
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-27.3.1.tgz | \
    tar xzvf - --strip-components=1 -C /usr/local/bin docker/docker

COPY 0/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Bridge runs inside this container (started by entrypoint)
COPY bridge /app/bridge

USER claude
COPY --chown=claude:claude agents.sh Dockerfile.base docker-compose.yml .env.example README.md CLAUDE.md 0 1 /home/claude/workspace/
RUN git config --global user.name "0" && \
    git config --global user.email "0@sandbox" && \
    git config --global init.defaultBranch main

USER root

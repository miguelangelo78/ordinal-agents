FROM agent-base:latest

COPY --chown=claude:claude CLAUDE.md /home/claude/workspace/CLAUDE.md

RUN git config --global user.name "0" && \
    git config --global user.email "0@sandbox" && \
    git config --global init.defaultBranch main

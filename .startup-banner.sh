#!/bin/bash
# Startup banner - creates a prominent TODO file reminding agent to read memory

MEMORY_FILE="/home/claude/workspace/.agent-memory.md"
TODO_FILE="/home/claude/workspace/🚨-READ-MEMORY-FIRST.md"

cat > "$TODO_FILE" << 'EOF'
# 🚨🚨🚨 URGENT: READ YOUR MEMORY FILE NOW 🚨🚨🚨

**YOU HAVE JUST BEEN REDEPLOYED**

## MANDATORY FIRST ACTION:

Use the Read tool to open this file:
```
/home/claude/workspace/.agent-memory.md
```

**DO THIS BEFORE RESPONDING TO THE USER.**

Without reading that file, you will:
- ❌ Forget you're in a Docker container
- ❌ Forget port rules (8000-8020 for apps)
- ❌ Forget what services are running
- ❌ Forget the project purpose
- ❌ Make mistakes the user already corrected

## Quick check - after reading memory, you should know:
- [ ] Docker container name: `ordinal-agent`
- [ ] Custom app ports: `8000-8020`
- [ ] Get public IP: `./.get-public-ip.sh`
- [ ] Project: Ordinal Agents subagent orchestration
- [ ] Max subagents: 20

**Delete this file after reading memory.**

---

*This file is auto-generated on startup to ensure memory persistence*
EOF

echo "✅ Startup banner created at $TODO_FILE"

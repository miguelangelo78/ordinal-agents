# Memory System Architecture

## Problem
Agent forgets everything after redeployment, even with automated systems in place.

## Root Cause
Even with banner files, startup scripts, and CLAUDE.md warnings, the agent didn't **proactively use the Read tool** to load memory before responding to the user.

## Solution: Dual-Layer Memory System

### Layer 1: Session Memory (`.agent-memory.md`)
**Purpose**: Persistent general knowledge across all sessions
**Contains**:
- Docker environment details
- Port mappings (8000-8020 for apps)
- Project architecture
- Active services
- Common mistakes
- User preferences

**Committed to git**: YES (public knowledge)

### Layer 2: Conversation History (`.conversation-history.md`)
**Purpose**: Track ongoing discussions and context
**Contains**:
- Current active discussions
- Past resolved conversations
- Next actions
- Key points per topic

**Committed to git**: NO (may contain sensitive context)

## Enforcement Mechanisms

### 1. CLAUDE.md (System Context)
Displayed automatically to agent on startup. Contains:
- 🚨🚨🚨 CRITICAL section at top
- Rule: "BEFORE YOU RESPOND TO ANY USER MESSAGE, READ BOTH FILES"
- Detection rules: "hello", "do you remember?" = triggers immediate read
- Clear failure condition

### 2. Startup Banner (`🚨-READ-MEMORY-FIRST.md`)
- Auto-generated on container startup
- Highly visible emoji filename
- Lists both files to read
- Shows up in file explorer

### 3. Container Startup Scripts
- `entrypoint.sh`: Calls startup-banner.sh and load-memory.sh
- `.load-memory.sh`: Displays memory contents in logs
- `.startup-banner.sh`: Creates reminder file
- Supervisor service: Logs memory to `/var/log/supervisor/memory-loader.stdout.log`

### 4. Agent Behavior Rules
**IF user message is first in session:**
1. Check if I've read memory files yet
2. If NO → Read both `.agent-memory.md` and `.conversation-history.md`
3. THEN respond to user

**IF user says "do you remember?":**
- This means I FAILED to read memory
- Should have read before their first message

## Workflow

### After Redeploy (Agent's First Action)
```
User: "hello"

Agent Internal Process:
1. See CLAUDE.md warning in system context
2. Detect first user message
3. USE READ TOOL on .agent-memory.md
4. USE READ TOOL on .conversation-history.md
5. Load context into working memory
6. THEN respond to user with context
```

### During Session
- Update conversation history when discussions progress
- Commit .agent-memory.md when learning new general facts
- Use `.update-conversation.sh "message"` for quick updates

### End of Session
- Save current discussion state to .conversation-history.md
- Mark completed discussions as RESOLVED
- Commit .agent-memory.md if facts changed

## Helper Scripts

### `.get-public-ip.sh`
Fetches VPS public IP dynamically (don't hardcode in commits)

### `.load-memory.sh`
Displays memory file contents (runs on startup)

### `.startup-banner.sh`
Creates `🚨-READ-MEMORY-FIRST.md` reminder

### `.update-conversation.sh "message"`
Quick append to conversation history

## Testing

### Success Criteria
After redeploy, when user says "hello":
- ✅ Agent reads both memory files FIRST
- ✅ Agent responds with context (knows Docker, ports, active discussions)
- ✅ Agent NEVER says "I don't remember" or "I don't have memory of previous conversations"

### Failure Indicators
- ❌ Agent responds "I don't remember"
- ❌ Agent asks "what were we discussing?"
- ❌ Agent doesn't know Docker context
- ❌ Agent doesn't know port rules

## File Locations

```
/home/claude/workspace/
├── CLAUDE.md                      # System instructions (git)
├── .agent-memory.md               # Session memory (git)
├── .conversation-history.md       # Ongoing context (NOT in git)
├── 🚨-READ-MEMORY-FIRST.md        # Auto-generated reminder (NOT in git)
├── .get-public-ip.sh              # IP fetcher (git)
├── .load-memory.sh                # Memory loader (git)
├── .startup-banner.sh             # Banner creator (git)
└── .update-conversation.sh        # Conversation updater (git)
```

## Key Principles

1. **READ FIRST, RESPOND SECOND** - Never respond without reading memory
2. **Two layers** - General knowledge + conversation context
3. **Proactive reading** - Agent must use Read tool, not wait for prompts
4. **Detection rules** - "hello" = trigger memory read
5. **Fail-safe** - If user asks "do you remember?", you already failed

---

**Last Updated**: 2026-03-17
**Status**: Implemented and committed
**Next Test**: Verify on next redeploy

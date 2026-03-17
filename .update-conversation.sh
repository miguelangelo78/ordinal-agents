#!/bin/bash
# Quick script to append to conversation history

HISTORY_FILE="/home/claude/workspace/.conversation-history.md"

if [ ! -f "$HISTORY_FILE" ]; then
    echo "❌ Conversation history file not found: $HISTORY_FILE"
    exit 1
fi

# If called with message, append it
if [ $# -gt 0 ]; then
    echo "" >> "$HISTORY_FILE"
    echo "**Update $(date -u +%Y-%m-%d\ %H:%M\ UTC)**: $*" >> "$HISTORY_FILE"
    echo "✅ Updated conversation history"
else
    echo "Usage: ./.update-conversation.sh \"Your update message\""
    echo "Example: ./.update-conversation.sh \"Implemented memory system fix\""
fi

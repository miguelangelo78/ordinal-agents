#!/bin/bash
# Memory loader - ensures agent reads persistent knowledge on startup
# This script should be called automatically or by the agent immediately after redeployment

MEMORY_FILE="/home/claude/workspace/.agent-memory.md"

echo "=================================================="
echo "🧠 LOADING AGENT PERSISTENT MEMORY"
echo "=================================================="
echo ""

if [ -f "$MEMORY_FILE" ]; then
    echo "✅ Memory file found: $MEMORY_FILE"
    echo ""
    echo "📖 MEMORY CONTENTS:"
    echo "--------------------------------------------------"
    cat "$MEMORY_FILE"
    echo ""
    echo "=================================================="
    echo "✅ Memory loaded successfully!"
    echo "=================================================="
else
    echo "❌ ERROR: Memory file not found at $MEMORY_FILE"
    echo "⚠️  Agent will operate without persistent knowledge!"
    exit 1
fi

#!/bin/bash
# Redeploy script for ordinal-agents
# This script pulls the latest changes and redeploys the agent container

set -e  # Exit on error

echo "🔄 Starting redeploy process..."
echo ""

# Change to workspace directory
cd "$(dirname "$0")"

# Pull latest changes from git
echo "📥 Pulling latest changes from git..."
git pull origin main
echo ""

# Stop the current agent container
echo "🛑 Stopping current agent container..."
docker compose stop agent
echo ""

# Remove the old container (keeps volumes)
echo "🗑️  Removing old container..."
docker compose rm -f agent
echo ""

# Rebuild the agent image
echo "🔨 Rebuilding agent image..."
docker compose build agent
echo ""

# Start the agent container
echo "🚀 Starting new agent container..."
docker compose up -d agent
echo ""

# Wait a few seconds for the container to start
echo "⏳ Waiting for agent to start..."
sleep 5
echo ""

# Check container status
echo "✅ Container status:"
docker compose ps agent
echo ""

# Show recent logs
echo "📋 Recent logs:"
docker compose logs --tail=20 agent
echo ""

echo "🎉 Redeploy complete!"
echo ""
echo "Access your agent at:"
echo "  - Main agent: http://localhost:3000"
echo "  - Open WebUI: http://localhost:3080"
echo ""

#!/bin/bash
set -e  # Exit on error

if [ $# -lt 2 ]; then
    echo "Usage: $0 <service-path> <command>"
    echo "Example: $0 services/utilities/dashy up -d"
    exit 1
fi

SERVICE_PATH="$1"
COMMAND="$2"
shift 2

# Validate service path exists
if [ ! -d "$SERVICE_PATH" ]; then
    echo "❌ Service path does not exist: $SERVICE_PATH"
    exit 1
fi

# Validate compose file exists
if [ ! -f "$SERVICE_PATH/docker-compose.yml" ]; then
    echo "❌ docker-compose.yml not found in: $SERVICE_PATH"
    exit 1
fi

# Get service name for display
SERVICE_NAME=$(basename "$SERVICE_PATH")

echo "🔄 Managing service: $SERVICE_NAME"
echo "📁 Path: $SERVICE_PATH"
echo "🎯 Command: $COMMAND $@"

cd "$SERVICE_PATH"

# Look for .env file in multiple locations (in order of preference)
ENV_FILE=""
if [ -f "$GITHUB_WORKSPACE/.env" ]; then
    ENV_FILE="$GITHUB_WORKSPACE/.env"
    echo "✅ Using .env from GitHub workspace"
elif [ -f "/workspace/.env" ]; then
    ENV_FILE="/workspace/.env"
    echo "✅ Using .env from workspace root"
elif [ -f "../../../.env" ]; then
    ENV_FILE="../../../.env"
    echo "✅ Using .env from relative path"
else
    echo "❌ .env file not found in any expected location"
    echo "📍 Checked locations:"
    echo "  - $GITHUB_WORKSPACE/.env"
    echo "  - /workspace/.env"
    echo "  - ../../../.env"
    exit 1
fi

echo "🔧 Running: docker-compose --env-file $ENV_FILE $COMMAND $@"
docker-compose --env-file "$ENV_FILE" "$COMMAND" "$@"

echo "✅ Command completed for $SERVICE_NAME"

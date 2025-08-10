#!/bin/bash
if [ $# -lt 2 ]; then
    echo "Usage: $0 <service-path> <command>"
    echo "Example: $0 services/utilities/dashy up -d"
    exit 1
fi

SERVICE_PATH="$1"
shift
cd "$SERVICE_PATH"
docker-compose --env-file ../../../.env "$@"

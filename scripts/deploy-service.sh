#!/bin/bash
# scripts/deploy-service.sh - Enhanced service deployment script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MAX_WAIT_TIME=120  # Maximum time to wait for service health check
HEALTH_CHECK_INTERVAL=5  # Interval between health checks

show_usage() {
    echo -e "${BLUE}Enhanced Service Deployment Script${NC}"
    echo
    echo -e "${YELLOW}Usage: $0 <service-path> [options]${NC}"
    echo
    echo -e "${GREEN}Options:${NC}"
    echo "  --force         Force deployment even if no changes detected"
    echo "  --pull-only     Only pull images without restarting"
    echo "  --no-health     Skip health checks"
    echo "  --wait-time N   Set custom wait time for health checks (default: 120s)"
    echo
    echo -e "${GREEN}Examples:${NC}"
    echo "  $0 services/utilities/dashy"
    echo "  $0 services/monitoring/grafana --force"
    echo "  $0 services/security/authentik --wait-time 180"
}

# Parse arguments
SERVICE_PATH=""
FORCE_DEPLOY=false
PULL_ONLY=false
SKIP_HEALTH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        --pull-only)
            PULL_ONLY=true
            shift
            ;;
        --no-health)
            SKIP_HEALTH=true
            shift
            ;;
        --wait-time)
            MAX_WAIT_TIME="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        -*)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$SERVICE_PATH" ]; then
                SERVICE_PATH="$1"
            else
                echo -e "${RED}❌ Multiple service paths provided${NC}"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [ -z "$SERVICE_PATH" ]; then
    echo -e "${RED}❌ Service path is required${NC}"
    show_usage
    exit 1
fi

# Validate service path exists
if [ ! -d "$SERVICE_PATH" ]; then
    echo -e "${RED}❌ Service path does not exist: $SERVICE_PATH${NC}"
    exit 1
fi

# Validate compose file exists
if [ ! -f "$SERVICE_PATH/docker-compose.yml" ]; then
    echo -e "${RED}❌ docker-compose.yml not found in: $SERVICE_PATH${NC}"
    exit 1
fi

# Extract service information
SERVICE_NAME=$(basename "$SERVICE_PATH")
CATEGORY=$(basename $(dirname "$SERVICE_PATH"))

echo -e "${BLUE}🚀 Deploying Service${NC}"
echo -e "${YELLOW}📁 Category: $CATEGORY${NC}"
echo -e "${YELLOW}🏷️ Service: $SERVICE_NAME${NC}"
echo -e "${YELLOW}📍 Path: $SERVICE_PATH${NC}"
echo

# FIXED find_env_file function
find_env_file() {
    local env_file=""
    
    # Look for .env file in multiple locations (in order of preference)
    # 1. Current directory (docker-compose directory)
    if [ -f "$(pwd)/.env" ]; then
        env_file="$(pwd)/.env"
        echo -e "${GREEN}✅ Using .env from current directory${NC}" >&2
    # 2. Workspace (GitHub Actions runner mount)
    elif [ -f "/workspace/.env" ]; then
        env_file="/workspace/.env"
        echo -e "${GREEN}✅ Using .env from workspace (GitHub runner)${NC}" >&2
    # 3. Docker-compose base directory
    elif [ -f "/mnt/user/appdata/docker-compose/.env" ]; then
        env_file="/mnt/user/appdata/docker-compose/.env"
        echo -e "${GREEN}✅ Using .env from docker-compose base directory${NC}" >&2
    # 4. GitHub workspace
    elif [ -f "$GITHUB_WORKSPACE/.env" ]; then
        env_file="$GITHUB_WORKSPACE/.env"
        echo -e "${GREEN}✅ Using .env from GitHub workspace${NC}" >&2
    # 5. Relative path fallback
    elif [ -f "../../../.env" ]; then
        env_file="../../../.env"
        echo -e "${GREEN}✅ Using .env from relative path${NC}" >&2
    else
        echo -e "${RED}❌ .env file not found in any expected location${NC}" >&2
        echo -e "${YELLOW}📍 Checked locations:${NC}" >&2
        echo "  - $(pwd)/.env" >&2
        echo "  - /workspace/.env" >&2
        echo "  - /mnt/user/appdata/docker-compose/.env" >&2
        echo "  - $GITHUB_WORKSPACE/.env" >&2
        echo "  - ../../../.env" >&2
        exit 1
    fi
    
    # ONLY echo the file path to stdout (this gets captured by the variable)
    echo "$env_file"
}

ENV_FILE=$(find_env_file)

# Change to service directory
cd "$SERVICE_PATH"

# Get list of current containers for this service
get_service_containers() {
    docker-compose --env-file "$ENV_FILE" ps -q 2>/dev/null || true
}

# Get service status
get_service_status() {
    docker-compose --env-file "$ENV_FILE" ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || echo "No containers running"
}

# Pre-deployment status
echo -e "${BLUE}📊 Pre-deployment Status:${NC}"
CONTAINERS_BEFORE=$(get_service_containers)
if [ ! -z "$CONTAINERS_BEFORE" ]; then
    get_service_status
else
    echo "No containers currently running for this service"
fi
echo

# Validate compose file
echo -e "${BLUE}🔍 Validating compose file...${NC}"
if ! docker-compose --env-file "$ENV_FILE" config >/dev/null 2>&1; then
    echo -e "${RED}❌ Invalid docker-compose.yml syntax${NC}"
    echo "Running validation for details:"
    docker-compose --env-file "$ENV_FILE" config
    exit 1
fi
echo -e "${GREEN}✅ Compose file syntax valid${NC}"

# Pull latest images
echo -e "${BLUE}📦 Pulling latest images...${NC}"
if docker-compose --env-file "$ENV_FILE" pull; then
    echo -e "${GREEN}✅ Images pulled successfully${NC}"
else
    echo -e "${YELLOW}⚠️ Some images could not be pulled (continuing anyway)${NC}"
fi

# Exit early if pull-only mode
if [ "$PULL_ONLY" = true ]; then
    echo -e "${GREEN}🎉 Pull-only mode complete!${NC}"
    exit 0
fi

# Check if restart is needed (unless forced)
RESTART_NEEDED=true
if [ "$FORCE_DEPLOY" = false ]; then
    echo -e "${BLUE}🔍 Checking if restart is needed...${NC}"
    
    # Get image IDs before and after pull
    CURRENT_IMAGES=$(docker-compose --env-file "$ENV_FILE" images -q 2>/dev/null | sort)
    
    # If containers are running, check if images changed
    if [ ! -z "$CONTAINERS_BEFORE" ]; then
        RUNNING_IMAGES=$(docker inspect --format='{{.Image}}' $CONTAINERS_BEFORE 2>/dev/null | sort || true)
        
        if [ "$CURRENT_IMAGES" = "$RUNNING_IMAGES" ]; then
            echo -e "${GREEN}ℹ️ No image updates detected, restart not needed${NC}"
            RESTART_NEEDED=false
        fi
    fi
fi

if [ "$RESTART_NEEDED" = true ]; then
    echo -e "${BLUE}🔄 Restarting service...${NC}"
    
    # Graceful shutdown
    echo "Stopping containers..."
    docker-compose --env-file "$ENV_FILE" down --timeout 30 || echo "Warning: Some containers took longer to stop"
    
    # Start services
    echo "Starting containers..."
    if docker-compose --env-file "$ENV_FILE" up -d; then
        echo -e "${GREEN}✅ Service started successfully${NC}"
    else
        echo -e "${RED}❌ Failed to start service${NC}"
        echo "Checking for error details..."
        docker-compose --env-file "$ENV_FILE" logs --tail 20
        exit 1
    fi
else
    echo -e "${GREEN}ℹ️ Service restart skipped (no changes detected)${NC}"
fi

# Health check
if [ "$SKIP_HEALTH" = false ] && [ "$RESTART_NEEDED" = true ]; then
    echo -e "${BLUE}🔍 Performing health checks...${NC}"
    
    # Wait for containers to start
    sleep 5
    
    # Get new container list
    NEW_CONTAINERS=$(get_service_containers)
    
    if [ -z "$NEW_CONTAINERS" ]; then
        echo -e "${RED}❌ No containers are running after deployment${NC}"
        exit 1
    fi
    
    # Check container health
    WAIT_TIME=0
    ALL_HEALTHY=false
    
    while [ $WAIT_TIME -lt $MAX_WAIT_TIME ]; do
        echo "Checking container health... (${WAIT_TIME}s/${MAX_WAIT_TIME}s)"
        
        UNHEALTHY_COUNT=0
        TOTAL_COUNT=0
        
        for container in $NEW_CONTAINERS; do
            ((TOTAL_COUNT++))
            
            # Check if container is still running
            if ! docker inspect "$container" >/dev/null 2>&1; then
                echo -e "${RED}⚠️ Container $container no longer exists${NC}"
                ((UNHEALTHY_COUNT++))
                continue
            fi
            
            # Get container status
            STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
            HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-health-check{{end}}' "$container" 2>/dev/null || echo "unknown")
            
            # FIXED VERSION:
            case $STATUS in
                "running")
                    if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "no-health-check" ]; then
                        echo -e "${GREEN}✅ $container: running ($HEALTH)${NC}"
                    elif [ "$HEALTH" = "starting" ]; then
                        echo -e "${YELLOW}⏳ $container: starting health checks${NC}"
                        # DON'T count as unhealthy - give it time!
                    elif [ "$HEALTH" = "unhealthy" ]; then
                        echo -e "${RED}⚠️ $container: running but unhealthy${NC}"
                        ((UNHEALTHY_COUNT++))
                    else
                        echo -e "${YELLOW}ℹ️ $container: running ($HEALTH)${NC}"
                        # Don't fail for unknown health states
                    fi
                    ;;
                "exited"|"dead")
                    echo -e "${RED}❌ $container: $STATUS${NC}"
                    ((UNHEALTHY_COUNT++))
                    ;;
                "restarting")
                    echo -e "${YELLOW}🔄 $container: restarting${NC}"
                    ((UNHEALTHY_COUNT++))
                    ;;
                *)
                    echo -e "${YELLOW}ℹ️ $container: $STATUS${NC}"
                    # Don't fail for unknown statuses during startup
                    ;;
            esac
        done
        
        if [ $UNHEALTHY_COUNT -eq 0 ]; then
            ALL_HEALTHY=true
            break
        fi
        
        # Wait before next check
        sleep $HEALTH_CHECK_INTERVAL
        WAIT_TIME=$((WAIT_TIME + HEALTH_CHECK_INTERVAL))
    done
    
    if [ "$ALL_HEALTHY" = true ]; then
        echo -e "${GREEN}✅ All containers are healthy!${NC}"
    else
        echo -e "${YELLOW}⚠️ Some containers may not be fully healthy yet${NC}"
        echo "This might be normal for services with longer startup times."
        
        # Show recent logs for debugging
        echo -e "${BLUE}📋 Recent logs for troubleshooting:${NC}"
        docker-compose --env-file "$ENV_FILE" logs --tail 10
    fi
fi

# Post-deployment status
echo
echo -e "${BLUE}📊 Post-deployment Status:${NC}"
get_service_status

# Show resource usage
echo
echo -e "${BLUE}💾 Resource Usage:${NC}"
if [ ! -z "$NEW_CONTAINERS" ]; then
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $NEW_CONTAINERS 2>/dev/null || echo "Could not retrieve stats"
fi

# Final summary
echo
echo -e "${GREEN}🎉 Deployment completed for $CATEGORY/$SERVICE_NAME${NC}"
echo -e "${YELLOW}📍 Service path: $SERVICE_PATH${NC}"

if [ "$RESTART_NEEDED" = true ]; then
    echo -e "${GREEN}✅ Service was restarted with latest images${NC}"
else
    echo -e "${BLUE}ℹ️ Service was up-to-date, no restart needed${NC}"
fi

# Return to original directory
cd - >/dev/null

echo -e "${GREEN}🚀 Deployment script completed successfully!${NC}"
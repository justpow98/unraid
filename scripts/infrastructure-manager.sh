#!/bin/bash
# infrastructure-manager.sh - Comprehensive management script for Docker Compose infrastructure
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Determine the correct working directory and .env file location
# Check if we're running in GitHub Actions environment
if [ "$GITHUB_ACTIONS" = "true" ] && [ -d "/workspace" ]; then
    WORKING_DIR="/workspace"
    ENV_FILE="/workspace/.env"
elif [ -d "/mnt/user/appdata/docker-compose" ]; then
    WORKING_DIR="/mnt/user/appdata/docker-compose"
    ENV_FILE="/mnt/user/appdata/docker-compose/.env"
else
    # Fallback to repo root for development
    WORKING_DIR="$REPO_ROOT"
    ENV_FILE="$REPO_ROOT/.env"
fi

# Service categories in deployment order
INFRASTRUCTURE_ORDER=(
    "infrastructure/networks"
    "infrastructure/redis" 
    "networking/nginx-proxy-manager"
    "networking/cloudflared"
    "security/authentik"
)

CORE_SERVICES=(
    "monitoring/prometheus"
    "monitoring/loki"
    "monitoring/grafana"
    "monitoring/promtail"
    "monitoring/uptimekuma"
)

show_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                   Infrastructure Manager                        ║"
    echo "║              Docker Compose Deployment System                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_usage() {
    show_banner
    echo -e "${YELLOW}Usage: $0 <command> [options]${NC}"
    echo
    echo -e "${GREEN}Deployment Commands:${NC}"
    echo "  deploy <service-path>     Deploy a specific service"
    echo "  deploy-category <cat>     Deploy all services in a category"
    echo "  deploy-all               Deploy all services (full infrastructure)"
    echo "  deploy-infrastructure    Deploy core infrastructure only"
    echo "  redeploy <service-path>  Force redeploy (pull + restart)"
    echo
    echo -e "${GREEN}Management Commands:${NC}"
    echo "  status [service-path]    Show service status"
    echo "  logs <service-path>      Show service logs"
    echo "  restart <service-path>   Restart a service"
    echo "  stop <service-path>      Stop a service"
    echo "  start <service-path>     Start a service"
    echo "  pull <service-path>      Pull latest images for service"
    echo
    echo -e "${GREEN}Information Commands:${NC}"
    echo "  list                     List all services"
    echo "  list-categories          List service categories"
    echo "  health                   Check overall system health"
    echo "  resources                Show resource usage"
    echo "  network-status          Show Docker network status"
    echo
    echo -e "${GREEN}Maintenance Commands:${NC}"
    echo "  check-updates           Check for container updates"
    echo "  backup                  Backup service configurations"
    echo "  cleanup                 Clean up unused Docker resources"
    echo "  validate                Validate all compose files"
    echo
    echo -e "${GREEN}Options:${NC}"
    echo "  --force                 Force operation even if not needed"
    echo "  --dry-run              Show what would be done without executing"
    echo "  --parallel             Run operations in parallel where possible"
    echo "  --verbose              Show detailed output"
    echo
    echo -e "${GREEN}Examples:${NC}"
    echo "  $0 deploy services/utilities/dashy"
    echo "  $0 deploy-category monitoring"
    echo "  $0 status"
    echo "  $0 health"
    echo "  $0 deploy-all --dry-run"
}

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_section() {
    echo
    echo -e "${PURPLE}━━━ $1 ━━━${NC}"
}

# Validation functions
validate_environment() {
    log_section "Environment Validation"
    
    # Change to the working directory
    cd "$WORKING_DIR"
    echo "📁 Working from: $(pwd)"
    
    # Check for services directory
    if [ ! -d "services" ]; then
        log_error "Services directory not found at $(pwd)/services"
        log_info "Please ensure docker-compose files are located at $COMPOSE_BASE_PATH"
        exit 1
    fi
    
    # Check for .env file
    if [ ! -f "$ENV_FILE" ]; then
        log_warning ".env file not found at $ENV_FILE"
        log_info "Looking for .env in alternate locations..."
        
        if [ -f "/workspace/.env" ]; then
            ENV_FILE="/workspace/.env"
            log_success "Found .env at /workspace/.env"
        elif [ -f "$WORKING_DIR/.env" ]; then
            ENV_FILE="$WORKING_DIR/.env"
            log_success "Found .env at $WORKING_DIR/.env"
        else
            log_error "No .env file found. Please ensure environment is configured."
            exit 1
        fi
    fi
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker not found. Please install Docker."
        exit 1
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_error "docker-compose not found. Please install docker-compose."
        exit 1
    fi
    
    # Test Docker access
    if ! docker ps >/dev/null 2>&1; then
        log_error "Cannot access Docker. Please check Docker daemon and permissions."
        exit 1
    fi
    
    log_success "Environment validation complete"
    log_info "Working directory: $WORKING_DIR"
    log_info "Environment file: $ENV_FILE"
}

# Service discovery functions
find_all_services() {
    find "$WORKING_DIR/services" -name "docker-compose.yml" -type f | while read compose_file; do
        service_path=$(dirname "$compose_file" | sed "s|$WORKING_DIR/||")
        echo "$service_path"
    done | sort
}

find_services_in_category() {
    local category="$1"
    find "$WORKING_DIR/services/$category" -name "docker-compose.yml" -type f 2>/dev/null | while read compose_file; do
        service_path=$(dirname "$compose_file" | sed "s|$WORKING_DIR/||")
        echo "$service_path"
    done | sort
}

get_service_info() {
    local service_path="$1"
    local category=$(echo "$service_path" | cut -d'/' -f2)
    local service=$(echo "$service_path" | cut -d'/' -f3)
    echo "$category|$service"
}

# Deployment functions
deploy_service() {
    local service_path="$1"
    local force="${2:-false}"
    
    if [ ! -d "$WORKING_DIR/$service_path" ]; then
        log_error "Service path not found: $service_path"
        return 1
    fi
    
    log_info "Deploying $service_path..."
    
    local deploy_args=""
    if [ "$force" = "true" ]; then
        deploy_args="--force"
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN: Would deploy $service_path"
        return 0
    fi
    
    if "$SCRIPT_DIR/deploy-service.sh" "$WORKING_DIR/$service_path" $deploy_args; then
        log_success "Successfully deployed $service_path"
        return 0
    else
        log_error "Failed to deploy $service_path"
        return 1
    fi
}

deploy_category() {
    local category="$1"
    local force="${2:-false}"
    
    log_section "Deploying Category: $category"
    
    local services=($(find_services_in_category "$category"))
    
    if [ ${#services[@]} -eq 0 ]; then
        log_warning "No services found in category: $category"
        return 1
    fi
    
    log_info "Found ${#services[@]} services in $category"
    
    local failed_count=0
    for service_path in "${services[@]}"; do
        if ! deploy_service "$service_path" "$force"; then
            ((failed_count++))
        fi
        sleep 2  # Brief pause between deployments
    done
    
    if [ $failed_count -eq 0 ]; then
        log_success "All services in $category deployed successfully"
    else
        log_warning "$failed_count service(s) failed to deploy in $category"
    fi
    
    return $failed_count
}

deploy_infrastructure() {
    log_section "Deploying Core Infrastructure"
    
    # Deploy in specific order
    for service_category in "${INFRASTRUCTURE_ORDER[@]}"; do
        if [ -d "$WORKING_DIR/services/$service_category" ]; then
            deploy_service "services/$service_category" true
            sleep 5  # Allow time for critical services to start
        else
            log_warning "Infrastructure service not found: $service_category"
        fi
    done
    
    log_section "Deploying Core Services"
    
    for service_category in "${CORE_SERVICES[@]}"; do
        if [ -d "$WORKING_DIR/services/$service_category" ]; then
            deploy_service "services/$service_category" true
            sleep 3
        else
            log_warning "Core service not found: $service_category"
        fi
    done
    
    log_success "Infrastructure deployment complete"
}

deploy_all() {
    local force="${1:-false}"
    
    log_section "Full Infrastructure Deployment"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN: Would deploy all services"
        find_all_services | while read service_path; do
            echo "  - $service_path"
        done
        return 0
    fi
    
    # Deploy infrastructure first
    deploy_infrastructure
    
    # Get all services
    local all_services=($(find_all_services))
    local infrastructure_services=()
    
    # Build list of infrastructure services to skip
    for infra in "${INFRASTRUCTURE_ORDER[@]}" "${CORE_SERVICES[@]}"; do
        infrastructure_services+=("services/$infra")
    done
    
    log_section "Deploying Application Services"
    
    local deployed_count=0
    local failed_count=0
    
    for service_path in "${all_services[@]}"; do
        # Skip infrastructure services (already deployed)
        local skip=false
        for infra in "${infrastructure_services[@]}"; do
            if [ "$service_path" = "$infra" ]; then
                skip=true
                break
            fi
        done
        
        if [ "$skip" = "true" ]; then
            continue
        fi
        
        if deploy_service "$service_path" "$force"; then
            ((deployed_count++))
        else
            ((failed_count++))
        fi
        
        sleep 2
    done
    
    log_section "Deployment Summary"
    log_info "Infrastructure services: ${#INFRASTRUCTURE_ORDER[@]} + ${#CORE_SERVICES[@]}"
    log_info "Application services deployed: $deployed_count"
    
    if [ $failed_count -eq 0 ]; then
        log_success "All services deployed successfully!"
    else
        log_warning "$failed_count service(s) failed to deploy"
    fi
}

# Status and monitoring functions
show_service_status() {
    local service_path="$1"
    
    if [ -z "$service_path" ]; then
        # Show overall status
        log_section "Overall System Status"
        
        local total_services=$(find_all_services | wc -l)
        local running_containers=$(docker ps -q | wc -l)
        
        echo "📊 Services: $total_services total"
        echo "🐳 Containers: $running_containers running"
        echo "🌐 Networks: $(docker network ls -q | wc -l) total"
        echo "💾 Volumes: $(docker volume ls -q | wc -l) total"
        
        echo
        echo "🔧 Top 10 services by resource usage:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -11
        
        return 0
    fi
    
    if [ ! -d "$WORKING_DIR/$service_path" ]; then
        log_error "Service path not found: $service_path"
        return 1
    fi
    
    log_section "Status: $service_path"
    
    cd "$WORKING_DIR/$service_path"
    
    # Show compose status
    echo "📋 Service Status:"
    docker-compose --env-file "$ENV_FILE" ps
    
    echo
    echo "📊 Resource Usage:"
    local containers=$(docker-compose --env-file "$ENV_FILE" ps -q)
    if [ ! -z "$containers" ]; then
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $containers
    else
        echo "No containers running"
    fi
}

show_system_health() {
    log_section "System Health Check"
    
    # Docker system health
    echo "🐳 Docker System Status:"
    docker system info --format "{{.ServerErrors}}" 2>/dev/null && echo "✅ Docker daemon healthy" || echo "❌ Docker daemon issues"
    
    echo
    echo "💾 Disk Usage:"
    docker system df
    
    echo
    echo "🔍 Container Health Summary:"
    
    local total_containers=0
    local healthy_containers=0
    local unhealthy_containers=0
    local no_health_check=0
    
    docker ps --format "{{.Names}}" | while read container; do
        if [ ! -z "$container" ]; then
            total_containers=$((total_containers + 1))
            health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-health-check{{end}}' "$container" 2>/dev/null)
            
            case $health in
                "healthy")
                    healthy_containers=$((healthy_containers + 1))
                    echo "✅ $container"
                    ;;
                "unhealthy")
                    unhealthy_containers=$((unhealthy_containers + 1))
                    echo "❌ $container"
                    ;;
                "starting")
                    echo "⏳ $container (starting)"
                    ;;
                "no-health-check")
                    no_health_check=$((no_health_check + 1))
                    echo "➖ $container (no health check)"
                    ;;
                *)
                    echo "❓ $container ($health)"
                    ;;
            esac
        fi
    done
}

# Maintenance functions
cleanup_system() {
    log_section "System Cleanup"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN: Would perform system cleanup"
        return 0
    fi
    
    log_info "Removing stopped containers..."
    docker container prune -f
    
    log_info "Removing unused images..."
    docker image prune -a -f --filter "until=24h"
    
    log_info "Removing unused networks..."
    docker network prune -f
    
    log_info "Removing unused volumes..."
    docker volume prune -f
    
    log_success "System cleanup complete"
    
    echo "📊 Current disk usage:"
    docker system df
}

validate_all_compose() {
    log_section "Validating All Compose Files"
    
    local validation_errors=0
    
    find_all_services | while read service_path; do
        echo "Validating: $service_path"
        
        cd "$REPO_ROOT/$service_path"
        
        if docker-compose --env-file "$ENV_FILE" config >/dev/null 2>&1; then
            echo "✅ $service_path"
        else
            echo "❌ $service_path"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    if [ $validation_errors -eq 0 ]; then
        log_success "All compose files are valid"
    else
        log_error "Found $validation_errors validation errors"
        exit 1
    fi
}

# Main command handling
COMMAND=""
SERVICE_PATH=""
FORCE=false
DRY_RUN=false
PARALLEL=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
            elif [ -z "$SERVICE_PATH" ]; then
                SERVICE_PATH="$1"
            else
                log_error "Too many arguments"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Show banner and validate environment
if [ "$COMMAND" != "help" ] && [ "$COMMAND" != "-h" ] && [ "$COMMAND" != "--help" ]; then
    show_banner
    validate_environment
fi

# Execute commands
case "$COMMAND" in
    "deploy")
        if [ -z "$SERVICE_PATH" ]; then
            log_error "Service path required for deploy command"
            exit 1
        fi
        deploy_service "$SERVICE_PATH" "$FORCE"
        ;;
    "deploy-category")
        if [ -z "$SERVICE_PATH" ]; then
            log_error "Category name required for deploy-category command"
            exit 1
        fi
        deploy_category "$SERVICE_PATH" "$FORCE"
        ;;
    "deploy-all")
        deploy_all "$FORCE"
        ;;
    "deploy-infrastructure")
        deploy_infrastructure
        ;;
    "redeploy")
        if [ -z "$SERVICE_PATH" ]; then
            log_error "Service path required for redeploy command"
            exit 1
        fi
        deploy_service "$SERVICE_PATH" true
        ;;
    "status")
        show_service_status "$SERVICE_PATH"
        ;;
    "health")
        show_system_health
        ;;
    "list")
        log_section "All Services"
        find_all_services | while read service; do
            info=$(get_service_info "$service")
            category=$(echo "$info" | cut -d'|' -f1)
            service_name=$(echo "$info" | cut -d'|' -f2)
            echo "📁 $category/$service_name"
        done
        ;;
    "list-categories")
        log_section "Service Categories"
        find "$WORKING_DIR/services" -mindepth 1 -maxdepth 1 -type d | while read category_dir; do
            category=$(basename "$category_dir")
            service_count=$(find "$category_dir" -name "docker-compose.yml" | wc -l)
            echo "📁 $category ($service_count services)"
        done
        ;;
    "cleanup")
        cleanup_system
        ;;
    "validate")
        validate_all_compose
        ;;
    "check-updates")
        log_info "Running update checker..."
        cd "$WORKING_DIR"
        python "$SCRIPT_DIR/check-updates.py"
        ;;
    "")
        log_error "Command required"
        show_usage
        exit 1
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac

log_success "Operation completed successfully!"

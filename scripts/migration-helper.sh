#!/bin/bash
# migration-helper.sh - Tool to help migrate Docker containers to compose repo

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_usage() {
    echo -e "${BLUE}Migration Helper - Convert Docker containers to compose${NC}"
    echo
    echo -e "${YELLOW}Usage: $0 <command> [arguments]${NC}"
    echo
    echo -e "${GREEN}Commands:${NC}"
    echo "  list                    - List all running containers"
    echo "  inspect <container>     - Export container configuration"
    echo "  scaffold <category> <service> - Create directory structure"
    echo "  template <type>         - Generate compose template"
    echo "  networks               - Create shared networks"
    echo "  validate <service-path> - Test a migrated service"
    echo
    echo -e "${GREEN}Examples:${NC}"
    echo "  $0 list"
    echo "  $0 inspect Nextcloud"
    echo "  $0 scaffold productivity nextcloud"
    echo "  $0 template database"
}

list_containers() {
    echo -e "${GREEN}📋 Current Docker containers:${NC}"
    echo
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -v "Docker-Compose-Runner\|FileBrowser\|dashy\|GoAccess-NPMLogs"
    echo
    echo -e "${BLUE}ℹ️ Excluding containers already in repo${NC}"
}

inspect_container() {
    local container_name="$1"
    if [ -z "$container_name" ]; then
        echo -e "${RED}❌ Container name required${NC}"
        return 1
    fi

    if ! docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "${RED}❌ Container '${container_name}' not found${NC}"
        return 1
    fi

    echo -e "${BLUE}🔍 Inspecting container: ${GREEN}${container_name}${NC}"
    
    # Create output directory
    mkdir -p "migration-data"
    
    # Export full container config
    docker inspect "${container_name}" > "migration-data/${container_name}_config.json"
    
    # Extract key information
    echo -e "${YELLOW}📦 Image:${NC}"
    docker inspect "${container_name}" --format '{{.Config.Image}}'
    
    echo -e "${YELLOW}🔌 Ports:${NC}"
    docker inspect "${container_name}" --format '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}}{{"\n"}}{{end}}' 2>/dev/null || echo "No exposed ports"
    
    echo -e "${YELLOW}📁 Volumes:${NC}"
    docker inspect "${container_name}" --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{"\n"}}{{end}}' 2>/dev/null || echo "No volumes"
    
    echo -e "${YELLOW}🌐 Networks:${NC}"
    docker inspect "${container_name}" --format '{{range $network, $config := .NetworkSettings.Networks}}{{$network}}{{"\n"}}{{end}}' 2>/dev/null || echo "Default network"
    
    echo -e "${YELLOW}⚙️ Environment:${NC}"
    docker inspect "${container_name}" --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' | head -20
    
    echo
    echo -e "${GREEN}✅ Configuration exported to: migration-data/${container_name}_config.json${NC}"
}

scaffold_service() {
    local category="$1"
    local service="$2"
    
    if [ -z "$category" ] || [ -z "$service" ]; then
        echo -e "${RED}❌ Category and service name required${NC}"
        echo -e "${YELLOW}Example: $0 scaffold productivity nextcloud${NC}"
        return 1
    fi

    local service_path="services/${category}/${service}"
    
    if [ -d "$service_path" ]; then
        echo -e "${YELLOW}⚠️ Directory already exists: ${service_path}${NC}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    echo -e "${BLUE}🏗️ Creating structure for: ${GREEN}${category}/${service}${NC}"
    
    # Create directory
    mkdir -p "$service_path"
    
    # Create basic docker-compose.yml template
    cat > "${service_path}/docker-compose.yml" << EOF

services:
  ${service}:
    image: # TODO: Add image with specific version tag
    container_name: ${service}
    restart: unless-stopped
    environment:
      - TZ=America/New_York
      - PUID=\${PUID}
      - PGID=\${PGID}
      - HOST_OS=Unraid
      - HOST_HOSTNAME=JP-Dell
      - HOST_CONTAINERNAME=${service}
      # TODO: Add service-specific environment variables
    volumes:
      - \${APPDATA_PATH}/${service}:/config
      # TODO: Add additional volume mounts
    ports:
      # TODO: Add port mappings
      - "8080:80"  # Example port mapping
    networks:
      - internal_net
    # Uncomment and configure if needed:
    # depends_on:
    #   - database
    # healthcheck:
    #   test: ["CMD-SHELL", "curl -f http://localhost:80 || exit 1"]
    #   interval: 30s
    #   timeout: 10s
    #   retries: 3

networks:
  internal_net:
    external: true
EOF

    # Create .env.example
    cat > "${service_path}/.env.example" << EOF
# .env.example for ${service}
# Copy this to the root .env file and configure

# Required for ${service}
APPDATA_PATH=/mnt/user/appdata

# Service-specific variables (update as needed)
# ${service^^}_ADMIN_PASSWORD=your_password_here
# ${service^^}_SECRET_KEY=your_secret_key_here
EOF

    echo -e "${GREEN}✅ Created service structure:${NC}"
    echo -e "  📁 ${service_path}/"
    echo -e "  📄 ${service_path}/docker-compose.yml"
    echo -e "  📄 ${service_path}/.env.example"
    echo
    echo -e "${YELLOW}📝 Next steps:${NC}"
    echo -e "  1. Edit docker-compose.yml with actual configuration"
    echo -e "  2. Update .env.example with required variables"
    echo -e "  3. Test with: ./manage-service.sh ${service_path} up -d"
}

generate_template() {
    local type="$1"
    
    case "$type" in
        "database")
            cat << 'EOF'
# Database Service Template


services:
  database:
    image: postgres:17  # or mariadb, mongo, redis
    container_name: service-database
    restart: unless-stopped
    environment:
      - POSTGRES_DB=${DB_NAME}
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - ${APPDATA_PATH}/database:/var/lib/postgresql/data
    networks:
      - db_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  db_net:
    external: true
EOF
            ;;
        "webapp")
            cat << 'EOF'
# Web Application Template


services:
  webapp:
    image: app:latest
    container_name: webapp
    restart: unless-stopped
    environment:
      - TZ=America/New_York
      - PUID=${PUID}
      - PGID=${PGID}
    volumes:
      - ${APPDATA_PATH}/webapp:/config
      - ${APPDATA_PATH}/webapp/data:/data
    ports:
      - "8080:80"
    networks:
      - internal_net
    depends_on:
      - database
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  internal_net:
    external: true
EOF
            ;;
        *)
            echo -e "${RED}❌ Unknown template type: $type${NC}"
            echo -e "${YELLOW}Available templates: database, webapp${NC}"
            return 1
            ;;
    esac
}

create_networks() {
    echo -e "${BLUE}🌐 Creating shared Docker networks...${NC}"
    
    mkdir -p "services/infrastructure/networks"
    
    cat > "services/infrastructure/networks/docker-compose.yml" << 'EOF'


# Shared networks for all services
# Run this first: ./manage-service.sh services/infrastructure/networks up -d

networks:
  # Public-facing services (exposed to internet)
  public_net:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.20.0.0/16

  # Internal services (backend communication)
  internal_net:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.21.0.0/16

  # Database network (databases only)
  db_net:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.22.0.0/16

  # Monitoring network (metrics and logs)
  monitoring_net:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.23.0.0/16
EOF

    echo -e "${GREEN}✅ Created network configuration${NC}"
    echo -e "${YELLOW}📝 To create networks, run:${NC}"
    echo -e "  ./manage-service.sh services/infrastructure/networks up -d"
}

validate_service() {
    local service_path="$1"
    
    if [ -z "$service_path" ]; then
        echo -e "${RED}❌ Service path required${NC}"
        return 1
    fi

    if [ ! -f "${service_path}/docker-compose.yml" ]; then
        echo -e "${RED}❌ docker-compose.yml not found in ${service_path}${NC}"
        return 1
    fi

    echo -e "${BLUE}🔍 Validating service: ${GREEN}${service_path}${NC}"
    
    # Check compose file syntax
    echo -e "${YELLOW}📝 Checking compose file syntax...${NC}"
    if ! docker-compose -f "${service_path}/docker-compose.yml" config >/dev/null 2>&1; then
        echo -e "${RED}❌ Invalid docker-compose.yml syntax${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Compose file syntax OK${NC}"
    
    # Check for required variables
    echo -e "${YELLOW}🔧 Checking environment variables...${NC}"
    if grep -q "\${" "${service_path}/docker-compose.yml"; then
        echo -e "${BLUE}ℹ️ Found environment variables in compose file${NC}"
        grep -o '\${[^}]*}' "${service_path}/docker-compose.yml" | sort -u
    fi
    
    # Test with dry run
    echo -e "${YELLOW}🧪 Testing deployment (dry run)...${NC}"
    cd "$service_path"
    if docker-compose --env-file "/mnt/user/appdata/docker-compose/.env" config >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Service configuration valid${NC}"
    else
        echo -e "${RED}❌ Service configuration issues found${NC}"
        docker-compose --env-file "/mnt/user/appdata/docker-compose/.env" config
        return 1
    fi
    cd - >/dev/null
    
    echo -e "${GREEN}✅ Service validation complete${NC}"
    echo -e "${YELLOW}📝 Ready to deploy with:${NC}"
    echo -e "  ./manage-service.sh ${service_path} up -d"
}

# Main command handling
case "${1:-}" in
    "list")
        list_containers
        ;;
    "inspect")
        inspect_container "$2"
        ;;
    "scaffold")
        scaffold_service "$2" "$3"
        ;;
    "template")
        generate_template "$2"
        ;;
    "networks")
        create_networks
        ;;
    "validate")
        validate_service "$2"
        ;;
    *)
        show_usage
        ;;
esac

#!/bin/bash
# fixed-export.sh - Fixed version avoiding subshell issues

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create export directory
EXPORT_DIR="container-export-fixed-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EXPORT_DIR"/{raw-configs,summaries,compose-ready}

echo -e "${BLUE}🔍 Fixed Container Export Script${NC}"
echo -e "${YELLOW}📁 Export directory: $EXPORT_DIR${NC}"
echo

# Get container list and save to file to avoid subshell issues
CONTAINER_LIST_FILE="$EXPORT_DIR/container-list.tmp"
docker ps --format "{{.Names}}" > "$CONTAINER_LIST_FILE"

CONTAINER_COUNT=$(wc -l < "$CONTAINER_LIST_FILE")
echo -e "${GREEN}📦 Found $CONTAINER_COUNT running containers${NC}"

# Create master summary file
MASTER_SUMMARY="$EXPORT_DIR/MASTER-SUMMARY.md"
{
    echo "# Container Export Summary - $(date)"
    echo
    echo "## 📊 Container Overview" 
    echo
    echo "| Container Name | Image | Ports | Networks | Database? |"
    echo "|----------------|--------|-------|----------|-----------|"
} > "$MASTER_SUMMARY"

# Function to safely extract container info
extract_container_safe() {
    local container_name="$1"
    local container_file="$EXPORT_DIR/raw-configs/${container_name}.json"
    local summary_file="$EXPORT_DIR/summaries/${container_name}-summary.txt"
    
    echo -e "${BLUE}📦 Exporting: ${GREEN}$container_name${NC}"
    
    # Export full docker inspect
    if ! docker inspect "$container_name" > "$container_file" 2>/dev/null; then
        echo -e "${RED}❌ Failed to inspect $container_name${NC}"
        return 1
    fi
    
    # Extract information safely with error handling
    {
        echo "=== CONTAINER: $container_name ==="
        echo
        
        echo "📋 BASIC INFO:"
        echo "Image: $(docker inspect "$container_name" --format '{{.Config.Image}}' 2>/dev/null || echo 'Unknown')"
        echo "Status: $(docker inspect "$container_name" --format '{{.State.Status}}' 2>/dev/null || echo 'Unknown')"
        echo "Restart: $(docker inspect "$container_name" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo 'Unknown')"
        echo "Privileged: $(docker inspect "$container_name" --format '{{.HostConfig.Privileged}}' 2>/dev/null || echo 'false')"
        echo "Network Mode: $(docker inspect "$container_name" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null || echo 'default')"
        echo
        
        echo "🌐 NETWORKS:"
        docker inspect "$container_name" --format '{{range $network, $config := .NetworkSettings.Networks}}{{$network}}: {{$config.IPAddress}}{{"\n"}}{{end}}' 2>/dev/null || echo "Default network"
        echo
        
        echo "🔌 PORTS:"
        docker inspect "$container_name" --format '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{if $conf}}{{(index $conf 0).HostPort}}{{else}}Internal only{{end}}{{"\n"}}{{end}}' 2>/dev/null || echo "No port mappings"
        echo
        
        echo "📁 VOLUMES:"
        docker inspect "$container_name" --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}, {{if .RW}}RW{{else}}RO{{end}}){{"\n"}}{{end}}' 2>/dev/null || echo "No volumes"
        echo
        
        echo "⚙️ ENVIRONMENT VARIABLES:"
        docker inspect "$container_name" --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' 2>/dev/null || echo "No environment variables"
        echo
        
        echo "🔧 SPECIAL CONFIG:"
        echo "Devices: $(docker inspect "$container_name" --format '{{.HostConfig.Devices}}' 2>/dev/null || echo '[]')"
        echo "Cap Add: $(docker inspect "$container_name" --format '{{.HostConfig.CapAdd}}' 2>/dev/null || echo '[]')"
        echo "Security Opt: $(docker inspect "$container_name" --format '{{.HostConfig.SecurityOpt}}' 2>/dev/null || echo '[]')"
        echo
        
    } > "$summary_file" 2>/dev/null
    
    # Add to master summary
    local image_short=$(docker inspect "$container_name" --format '{{.Config.Image}}' 2>/dev/null | cut -d':' -f1 || echo "Unknown")
    local ports_summary=$(docker inspect "$container_name" --format '{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{(index $conf 0).HostPort}}:{{$p}} {{end}}{{end}}' 2>/dev/null | sed 's/ *$//' || echo "None")
    local networks_summary=$(docker inspect "$container_name" --format '{{range $network, $config := .NetworkSettings.Networks}}{{$network}} {{end}}' 2>/dev/null | sed 's/ *$//' || echo "Default")
    local is_database="No"
    
    # Check if it's a database
    if echo "$image_short" | grep -qE "(postgres|mysql|mariadb|mongo|redis)"; then
        is_database="Yes"
    fi
    
    echo "| $container_name | $image_short | $ports_summary | $networks_summary | $is_database |" >> "$MASTER_SUMMARY"
    
    return 0
}

# Process containers using a proper while loop (not with pipe)
COUNTER=1
SUCCESS_COUNT=0
FAILED_COUNT=0

# Read from file instead of pipe to avoid subshell
while IFS= read -r container_name; do
    if [ ! -z "$container_name" ]; then
        echo -e "${YELLOW}[$COUNTER/$CONTAINER_COUNT]${NC} Processing: $container_name"
        
        if extract_container_safe "$container_name"; then
            ((SUCCESS_COUNT++))
            echo -e "${GREEN}✅ Success${NC}"
        else
            ((FAILED_COUNT++))
            echo -e "${RED}❌ Failed${NC}"
        fi
        
        ((COUNTER++))
        echo
        
        # Small delay to prevent overwhelming
        sleep 0.2
        
        # Progress update every 10 containers
        if [ $((COUNTER % 10)) -eq 0 ]; then
            echo -e "${BLUE}📊 Progress: $SUCCESS_COUNT successes, $FAILED_COUNT failures${NC}"
        fi
    fi
done < "$CONTAINER_LIST_FILE"

# Generate categorization
{
    echo
    echo "## 📂 Suggested Categories"
    echo
    
    echo "### 🗄️ Infrastructure/Databases:"
    grep -E "(postgres|mysql|mariadb|mongo|redis)" "$CONTAINER_LIST_FILE" | sed 's/^/- /' || echo "- None found"
    
    echo
    echo "### 🌐 Networking:"
    grep -iE "(nginx|proxy|pihole|cloudflare|traefik)" "$CONTAINER_LIST_FILE" | sed 's/^/- /' || echo "- None found"
    
    echo
    echo "### 🔐 Security:"
    grep -iE "(authentik|vault|bitwarden|auth)" "$CONTAINER_LIST_FILE" | sed 's/^/- /' || echo "- None found"
    
    echo
    echo "### 📊 Monitoring:"
    grep -iE "(grafana|prometheus|uptime|monitor|loki)" "$CONTAINER_LIST_FILE" | sed 's/^/- /' || echo "- None found"
    
    echo
    echo "### 🎬 Media:"
    grep -iE "(immich|plex|jellyfin|romm|spotify)" "$CONTAINER_LIST_FILE" | sed 's/^/- /' || echo "- None found"
    
    echo
    echo "### 📋 Productivity:"
    grep -iE "(nextcloud|actual|wiki|office|duplicati)" "$CONTAINER_LIST_FILE" | sed 's/^/- /' || echo "- None found"
    
    echo
    echo "### 🏠 Home Automation:"
    grep -iE "(home.assistant|zigbee|mqtt|matter)" "$CONTAINER_LIST_FILE" | sed 's/^/- /' || echo "- None found"
    
} >> "$MASTER_SUMMARY"

# Final summary
{
    echo
    echo "## 📋 Export Summary"
    echo
    echo "- **Total Containers**: $CONTAINER_COUNT"
    echo "- **Successfully Exported**: $SUCCESS_COUNT"
    echo "- **Failed**: $FAILED_COUNT"
    echo "- **Export Date**: $(date)"
    echo "- **Export Directory**: $EXPORT_DIR"
    echo
    echo "## 📁 Files Created"
    echo
    echo "- \`MASTER-SUMMARY.md\` - This overview file"
    echo "- \`raw-configs/\` - Full JSON configurations"
    echo "- \`summaries/\` - Human-readable summaries"
    echo "- \`container-list.tmp\` - Simple container list"
    
} >> "$MASTER_SUMMARY"

# Create additional helpful files
echo "Creating additional summary files..."

# Current images list
{
    echo "# Current Image Versions - $(date)"
    echo
    while IFS= read -r container; do
        if [ ! -z "$container" ]; then
            image=$(docker inspect "$container" --format '{{.Config.Image}}' 2>/dev/null || echo "Unknown")
            echo "$container: $image"
        fi
    done < "$CONTAINER_LIST_FILE"
} > "$EXPORT_DIR/current-images.txt"

# Network summary
{
    echo "# Network Summary - $(date)"
    echo
    echo "## Available Networks:"
    docker network ls
    echo
    echo "## Container Network Assignments:"
    while IFS= read -r container; do
        if [ ! -z "$container" ]; then
            echo "=== $container ==="
            docker inspect "$container" --format '{{range $network, $config := .NetworkSettings.Networks}}{{$network}}: {{$config.IPAddress}}{{"\n"}}{{end}}' 2>/dev/null || echo "Default network"
            echo
        fi
    done < "$CONTAINER_LIST_FILE"
} > "$EXPORT_DIR/network-summary.txt"

# Clean up temp file
rm -f "$CONTAINER_LIST_FILE"

# Create archive
echo "Creating archive..."
if command -v zip >/dev/null 2>&1; then
    zip -r "${EXPORT_DIR}.zip" "$EXPORT_DIR" >/dev/null 2>&1
    echo -e "${GREEN}📦 Archive created: ${EXPORT_DIR}.zip${NC}"
fi

echo
echo -e "${GREEN}🎉 Export Complete!${NC}"
echo
echo -e "${BLUE}📊 Final Results:${NC}"
echo -e "  📁 Export directory: ${YELLOW}$EXPORT_DIR${NC}"
echo -e "  ✅ Successful exports: ${GREEN}$SUCCESS_COUNT${NC}"
echo -e "  ❌ Failed exports: ${RED}$FAILED_COUNT${NC}"
echo
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. Review: cat $EXPORT_DIR/MASTER-SUMMARY.md"
echo "2. Check summaries: ls $EXPORT_DIR/summaries/"
echo "3. Share the export directory or .zip file for docker-compose generation"
echo
echo -e "${GREEN}🚀 Ready for docker-compose.yml generation!${NC}"

#!/usr/bin/env python3
import os
import yaml
import requests
import re
from datetime import datetime
import glob
from typing import Dict, List, Optional, Tuple
import time

# Comprehensive repository mappings for GitHub releases
REPO_MAPPINGS = {
    # Utilities
    'lissy93/dashy': 'lissy93/dashy',
    'filebrowser/filebrowser': 'filebrowser/filebrowser',
    'xavierh/goaccess-for-nginxproxymanager': 'xavier-hernandez/goaccess-for-nginxproxymanager',
    'lscr.io/linuxserver/duplicati': 'linuxserver/docker-duplicati',
    'honeygain/honeygain': 'honeygain/honeygain-docker',
    
    # Security
    'vaultwarden/server': 'dani-garcia/vaultwarden',
    'beryju/authentik': 'goauthentik/authentik',
    
    # Media
    'ghcr.io/imagegenius/immich': 'imagegenius/docker-immich',
    'rommapp/romm': 'rommapp/romm',
    
    # Productivity
    'nextcloud': 'nextcloud/server',
    'actualbudget/actual-server': 'actualbudget/actual-server',
    'requarks/wiki': 'requarks/wiki',
    'onlyoffice/documentserver': 'ONLYOFFICE/DocumentServer',
    
    # Monitoring
    'grafana/grafana': 'grafana/grafana',
    'prom/prometheus': 'prometheus/prometheus',
    'grafana/loki': 'grafana/loki',
    'grafana/promtail': 'grafana/loki',  # Promtail is part of Loki project
    'louislam/uptime-kuma': 'louislam/uptime-kuma',
    'ghcr.io/bigboot/autokuma': 'BigBoot/AutoKuma',
    
    # IoT
    'ghcr.io/home-assistant/home-assistant': 'home-assistant/core',
    'eclipse-mosquitto': 'eclipse/mosquitto',
    'koenkk/zigbee2mqtt': 'Koenkk/zigbee2mqtt',
    'ghcr.io/home-assistant-libs/python-matter-server': 'home-assistant-libs/python-matter-server',
    
    # Automotive
    'teslamate/teslamate': 'adriankumpf/teslamate',
    'teslamate/grafana': 'adriankumpf/teslamate',
    
    # Infrastructure
    'postgres': 'postgres/postgres',
    'redis': 'redis/redis',
    'mariadb': 'MariaDB/server',
    'bitnami/redis': 'bitnami/containers',
    
    # Networking
    'zoeyvid/npmplus': 'ZoeyVid/NPMplus',
    'figro/unraid-cloudflared-tunnel': 'cloudflare/cloudflared',
    
    # Automation
    'myoung34/github-runner': 'myoung34/docker-github-actions-runner',
}

# Custom version patterns for different image types
VERSION_PATTERNS = {
    'dashy': r'^release-\d+\.\d+\.\d+$',
    'filebrowser': r'^v\d+\.\d+\.\d+$',
    'uptimekuma': r'^\d+\.\d+\.\d+$',
    'grafana': r'^\d+\.\d+\.\d+$',
    'prometheus': r'^v\d+\.\d+\.\d+$',
    'loki': r'^\d+\.\d+\.\d+$',
    'promtail': r'^\d+\.\d+\.\d+$',
    'authentik': r'^\d{4}\.\d+\.\d+$',  # Year-based versioning
    'vaultwarden': r'^\d+\.\d+\.\d+$',
    'nextcloud': r'^\d+\.\d+\.\d+$',
    'teslamate': r'^\d+\.\d+\.\d+$',
    'home-assistant': r'^\d{4}\.\d+$',  # Year.month versioning
    'zigbee2mqtt': r'^\d+\.\d+\.\d+$',
    'matter-server': r'^\d+\.\d+\.\d+$',
    'redis': r'^\d+\.\d+(\.\d+)?(-alpine)?$',
    'postgres': r'^\d+(\.\d+)?$',
    'mariadb': r'^\d+\.\d+\.\d+$',
    'immich': r'^\d+\.\d+\.\d+$',
    'romm': r'^\d+\.\d+\.\d+$',
    'actualserver': r'^\d+\.\d+\.\d+$',
    'wikijs': r'^\d+\.\d+\.\d+$',
    'onlyoffice': r'^\d+\.\d+\.\d+$',
    'duplicati': r'^\d+\.\d+\.\d+$',
    'mosquitto': r'^\d+\.\d+\.\d+$',
    'npmplus': r'^\d+$',  # Single number versioning
    'cloudflared': r'^\d{4}\.\d+\.\d+$',  # Year-based
    'github-runner': r'^v\d+\.\d+\.\d+$',
    'autokuma': r'^\d+\.\d+\.\d+$',
}

def get_image_key(image_name: str) -> str:
    """Extract key from image name for pattern matching."""
    # Remove registry prefixes
    clean_name = image_name.replace('ghcr.io/', '').replace('lscr.io/', '')
    clean_name = clean_name.replace('docker.io/', '').replace('quay.io/', '')
    
    # Extract service name
    if '/' in clean_name:
        parts = clean_name.split('/')
        return parts[-1].split(':')[0]  # Get last part, remove tag
    return clean_name.split(':')[0]

def get_latest_docker_tag(image_name: str) -> Optional[str]:
    """Get the latest tag for a Docker image with intelligent pattern matching."""
    try:
        # Handle different registry formats
        if image_name.startswith('ghcr.io/'):
            registry_path = image_name.replace('ghcr.io/', '')
        elif image_name.startswith('lscr.io/'):
            registry_path = image_name.replace('lscr.io/', '')
        elif '/' not in image_name:
            registry_path = f"library/{image_name}"
        else:
            registry_path = image_name
        
        # For GitHub Container Registry
        if image_name.startswith('ghcr.io/'):
            return get_ghcr_latest_tag(registry_path)
        
        # For Docker Hub
        url = f"https://registry.hub.docker.com/v2/repositories/{registry_path}/tags"
        params = {"page_size": 100, "ordering": "last_updated"}
        
        response = requests.get(url, timeout=15)
        if response.status_code != 200:
            print(f"Warning: Could not fetch tags for {image_name} (status: {response.status_code})")
            return None
        
        tags = response.json().get("results", [])
        image_key = get_image_key(image_name)
        
        # Try to find appropriate pattern
        pattern = VERSION_PATTERNS.get(image_key)
        if pattern:
            for tag in tags:
                tag_name = tag["name"]
                if re.match(pattern, tag_name):
                    return tag_name
        
        # Fallback: generic semantic versioning
        for tag in tags:
            tag_name = tag["name"]
            if re.match(r'^\d+\.\d+(\.\d+)?$', tag_name):
                return tag_name
            elif re.match(r'^v\d+\.\d+(\.\d+)?$', tag_name):
                return tag_name
        
        return None
        
    except Exception as e:
        print(f"Error checking {image_name}: {e}")
        return None

def get_ghcr_latest_tag(registry_path: str) -> Optional[str]:
    """Get latest tag from GitHub Container Registry."""
    try:
        # Extract owner and package from registry path
        parts = registry_path.split('/')
        if len(parts) < 2:
            return None
        
        owner = parts[0]
        package = parts[1]
        
        # Use GitHub API to get package versions
        url = f"https://api.github.com/users/{owner}/packages/container/{package}/versions"
        headers = {"Accept": "application/vnd.github.v3+json"}
        
        response = requests.get(url, headers=headers, timeout=15)
        if response.status_code != 200:
            return None
        
        versions = response.json()
        if not versions:
            return None
        
        # Find the latest version with a semantic version tag
        for version in versions:
            tags = version.get('metadata', {}).get('container', {}).get('tags', [])
            for tag in tags:
                if re.match(r'^\d+\.\d+(\.\d+)?$', tag) or re.match(r'^v\d+\.\d+(\.\d+)?$', tag):
                    return tag
        
        return None
        
    except Exception as e:
        print(f"Error checking GHCR {registry_path}: {e}")
        return None

def get_github_releases(repo_name: str, old_version: str, new_version: str) -> Optional[List[Dict]]:
    """Get GitHub releases between two versions."""
    try:
        url = f"https://api.github.com/repos/{repo_name}/releases"
        headers = {"Accept": "application/vnd.github.v3+json"}
        response = requests.get(url, headers=headers, timeout=15)
        
        if response.status_code != 200:
            return None
        
        releases = response.json()
        changes = []
        
        # Clean version strings for comparison
        old_clean = old_version.replace('release-', '').replace('v', '').replace('-alpine', '')
        new_clean = new_version.replace('release-', '').replace('v', '').replace('-alpine', '')
        
        for release in releases:
            tag = release.get('tag_name', '').replace('release-', '').replace('v', '').replace('-alpine', '')
            
            # Include releases between old and new versions
            if tag == new_clean or (old_clean < tag <= new_clean):
                changes.append({
                    'version': release.get('tag_name', ''),
                    'name': release.get('name', ''),
                    'body': (release.get('body', '')[:300] + '...' 
                           if len(release.get('body', '')) > 300 
                           else release.get('body', '')),
                    'url': release.get('html_url', ''),
                    'published': release.get('published_at', '')[:10]
                })
        
        return changes[:3]  # Limit to 3 most recent
        
    except Exception as e:
        print(f"Error getting releases for {repo_name}: {e}")
    return None

def check_service_for_updates(compose_file_path: str) -> Tuple[List[Dict], bool]:
    """Check a specific docker-compose file for updates."""
    updates = []
    
    try:
        with open(compose_file_path, 'r') as f:
            compose_data = yaml.safe_load(f)
    except Exception as e:
        print(f"Error reading {compose_file_path}: {e}")
        return updates, False
    
    if 'services' not in compose_data:
        return updates, False
    
    modified = False
    
    for service_name, service_config in compose_data['services'].items():
        if 'image' not in service_config:
            continue
            
        current_image = service_config['image']
        
        # Skip latest tags
        if current_image.endswith(':latest'):
            print(f"Skipping {service_name}: uses ':latest' tag")
            continue
        
        # Parse image name and tag
        if ':' in current_image:
            image_name, current_tag = current_image.rsplit(':', 1)
        else:
            print(f"Skipping {service_name}: no tag specified")
            continue
        
        print(f"Checking {service_name} ({current_image})...")
        
        # Get latest version
        latest_tag = get_latest_docker_tag(image_name)
        
        if latest_tag and latest_tag != current_tag:
            print(f"  Update available: {current_tag} -> {latest_tag}")
            
            # Get changelog if we have repo mapping
            changelog = None
            repo_name = REPO_MAPPINGS.get(image_name)
            if repo_name:
                changelog = get_github_releases(repo_name, current_tag, latest_tag)
            
            # Update the compose file
            service_config['image'] = f"{image_name}:{latest_tag}"
            modified = True
            
            updates.append({
                'service': service_name,
                'file': compose_file_path,
                'old_version': current_tag,
                'new_version': latest_tag,
                'image': image_name,
                'changelog': changelog,
                'repo': repo_name
            })
        else:
            if latest_tag:
                print(f"  Up to date: {current_tag}")
            else:
                print(f"  Could not check: {current_tag}")
        
        # Rate limiting
        time.sleep(0.5)
    
    # Save modified file
    if modified:
        try:
            with open(compose_file_path, 'w') as f:
                yaml.dump(compose_data, f, default_flow_style=False, sort_keys=False)
        except Exception as e:
            print(f"Error writing {compose_file_path}: {e}")
            return updates, False
    
    return updates, modified

def main():
    """Main function to check all services for updates."""
    all_updates = []
    
    # Define the base path for docker-compose files
    # Check if we're running in GitHub Actions environment
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        COMPOSE_BASE_PATH = '/workspace'
    else:
        COMPOSE_BASE_PATH = '/mnt/user/appdata/docker-compose'
    
    # Check if we're running from the mounted path or need to change directory
    if os.path.exists(COMPOSE_BASE_PATH):
        os.chdir(COMPOSE_BASE_PATH)
        compose_files = glob.glob('services/**/docker-compose.yml', recursive=True)
    else:
        # Fallback to current directory (for development/testing)
        compose_files = glob.glob('services/**/docker-compose.yml', recursive=True)
    
    print(f"🔍 Checking {len(compose_files)} services for updates...")
    print(f"📁 Base path: {os.getcwd()}")
    print("=" * 50)
    
    for compose_file in sorted(compose_files):
        category = compose_file.split('/')[1] if len(compose_file.split('/')) > 1 else 'unknown'
        service = compose_file.split('/')[2] if len(compose_file.split('/')) > 2 else 'unknown'
        
        print(f"\n📁 {category}/{service}")
        print(f"   File: {compose_file}")
        
        updates, modified = check_service_for_updates(compose_file)
        if updates:
            all_updates.extend(updates)
            print(f"   ✅ {len(updates)} update(s) found")
        else:
            print(f"   ℹ️ No updates available")
    
    print("\n" + "=" * 50)
    
    # Generate PR summary
    if all_updates:
        summary = generate_update_summary(all_updates)
        
        # Set GitHub Actions environment variables
        env_file = os.environ.get('GITHUB_ENV', '/tmp/github_env')
        with open(env_file, 'a') as f:
            f.write("UPDATES_FOUND=true\n")
            f.write(f"UPDATE_DATE={datetime.now().strftime('%Y-%m-%d')}\n")
            f.write(f"UPDATE_SUMMARY={summary}\n")
        
        print(f"✅ Found {len(all_updates)} total updates!")
        
        # Group by category for summary
        by_category = {}
        for update in all_updates:
            category = update['file'].split('/')[1]
            if category not in by_category:
                by_category[category] = []
            by_category[category].append(update)
        
        for category, updates in by_category.items():
            print(f"\n📁 {category.upper()}:")
            for update in updates:
                print(f"  - {update['service']}: {update['old_version']} → {update['new_version']}")
    else:
        env_file = os.environ.get('GITHUB_ENV', '/tmp/github_env')
        with open(env_file, 'a') as f:
            f.write("UPDATES_FOUND=false\n")
        print("ℹ️ All services are up to date!")

def generate_update_summary(all_updates: List[Dict]) -> str:
    """Generate a formatted summary for the PR description."""
    
    # Group updates by category
    by_category = {}
    for update in all_updates:
        category = update['file'].split('/')[1]
        if category not in by_category:
            by_category[category] = []
        by_category[category].append(update)
    
    summary = "## 📋 Updated Services\\n\\n"
    summary += f"**Total Updates**: {len(all_updates)} services across {len(by_category)} categories\\n\\n"
    
    # Category overview
    summary += "### 📊 Updates by Category\\n\\n"
    for category, updates in sorted(by_category.items()):
        summary += f"- **{category.title()}**: {len(updates)} update(s)\\n"
    summary += "\\n"
    
    # Detailed updates by category
    for category, updates in sorted(by_category.items()):
        summary += f"### 📁 {category.title()} Services\\n\\n"
        
        for update in updates:
            summary += f"#### 🔄 {update['service']} ({update['old_version']} → {update['new_version']})\\n"
            summary += f"**Image**: `{update['image']}`\\n"
            
            if update['repo']:
                summary += f"**Repository**: [{update['repo']}](https://github.com/{update['repo']})\\n"
            
            if update['changelog']:
                summary += "\\n**Recent Changes**:\\n"
                for change in update['changelog']:
                    summary += f"- **{change['version']}** ({change['published']}): {change['name']}\\n"
                    if change['body']:
                        # Clean up changelog body
                        body = change['body'].replace('\\n', ' ').replace('\\r', '')
                        summary += f"  {body}\\n"
                    summary += f"  [View Release]({change['url']})\\n"
            else:
                summary += "\\n**Changelog**: Check repository releases manually\\n"
            summary += "\\n"
        
        summary += "---\\n\\n"
    
    return summary

if __name__ == "__main__":
    main()
#!/usr/bin/env python3
import os
import yaml
import requests
import re
from datetime import datetime
import glob
from typing import Dict, List, Optional, Tuple
import time
import base64
import json
import html
from packaging import version

# Enhanced repository mappings for GitHub releases
REPO_MAPPINGS = {
    # Utilities
    'lissy93/dashy': 'lissy93/dashy',
    'filebrowser/filebrowser': 'filebrowser/filebrowser',
    'xavierh/goaccess-for-nginxproxymanager': 'xavier-hernandez/goaccess-for-nginxproxymanager',
    'lscr.io/linuxserver/duplicati': 'linuxserver/docker-duplicati',
    'honeygain/honeygain': 'honeygain/honeygain-docker',
    
    # Security
    'vaultwarden/server': 'dani-garcia/vaultwarden',
    'goauthentik/server': 'goauthentik/server',
    
    # Media
    'ghcr.io/imagegenius/immich': 'imagegenius/docker-immich',
    'rommapp/romm': 'rommapp/romm',
    
    # Productivity
    'nextcloud': 'nextcloud/server',
    'actualbudget/actual-server': 'actualbudget/actual-server',
    'requarks/wiki': 'requarks/wiki',
    
    # Monitoring
    'grafana/grafana': 'grafana/grafana',
    'prom/prometheus': 'prometheus/prometheus',
    'grafana/loki': 'grafana/loki',
    'grafana/promtail': 'grafana/loki',
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

# Enhanced version patterns
VERSION_PATTERNS = {
    'dashy': r'^release-\d+\.\d+\.\d+$',
    'filebrowser': r'^v\d+\.\d+\.\d+$',
    'uptimekuma': r'^\d+\.\d+\.\d+$',
    'grafana': r'^\d+\.\d+\.\d+$',
    'prometheus': r'^v\d+\.\d+\.\d+$',
    'loki': r'^\d+\.\d+\.\d+$',
    'promtail': r'^\d+\.\d+\.\d+$',
    'authentik': r'^\d{4}\.\d+\.\d+$',
    'vaultwarden': r'^\d+\.\d+\.\d+$',
    'nextcloud': r'^\d+\.\d+\.\d+$',
    'teslamate': r'^\d+\.\d+\.\d+$',
    'home-assistant': r'^\d{4}\.\d+$',
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
    'npmplus': r'^\d+$',
    'cloudflared': r'^\d{4}\.\d+\.\d+$',
    'github-runner': r'^v\d+\.\d+\.\d+$',
    'autokuma': r'^\d+\.\d+\.\d+$',
}

def compare_versions(current: str, latest: str) -> bool:
    """Compare two version strings and return True if latest > current"""
    try:
        current_clean = clean_version(current)
        latest_clean = clean_version(latest)
        return version.parse(latest_clean) > version.parse(current_clean)
    except Exception as e:
        print(f"Version comparison error: {current} vs {latest}: {e}")
        return False

def clean_version(ver: str) -> str:
    """Clean version string for comparison"""
    import re
    ver = re.sub(r'^(release-|v)', '', ver)
    ver = re.sub(r'(-alpine|-slim)$', '', ver)
    return ver

class RateLimitManager:
    """Manages rate limiting across different registries"""
    def __init__(self):
        self.last_request = {}
        self.delays = {
            'dockerhub': 2.0,     # 2 seconds between Docker Hub requests
            'ghcr': 3.0,          # 3 seconds between GHCR requests
            'github_api': 1.0,    # 1 second between GitHub API requests
            'default': 0.5        # 0.5 seconds for other registries
        }
    
    def wait_if_needed(self, registry_type: str):
        """Wait if needed to respect rate limits"""
        now = time.time()
        last = self.last_request.get(registry_type, 0)
        delay = self.delays.get(registry_type, self.delays['default'])
        
        if now - last < delay:
            time.sleep(delay - (now - last))
        
        self.last_request[registry_type] = time.time()

def get_auth_headers() -> Dict[str, str]:
    """Get authentication headers for various registries"""
    headers = {
        'User-Agent': 'Docker-Update-Checker/1.0'
    }
    
    # GitHub token for GHCR and GitHub API
    github_token = os.environ.get('GITHUB_TOKEN') or os.environ.get('GITHUB_ACCESS_TOKEN')
    if github_token:
        headers['Authorization'] = f'token {github_token}'
    
    return headers

def get_docker_hub_auth_headers() -> Dict[str, str]:
    """Get Docker Hub authentication headers if credentials available"""
    headers = {'User-Agent': 'Docker-Update-Checker/1.0'}
    
    username = os.environ.get('DOCKER_HUB_USERNAME')
    password = os.environ.get('DOCKER_HUB_PASSWORD')
    
    if username and password:
        # Create basic auth header
        credentials = f"{username}:{password}"
        encoded_credentials = base64.b64encode(credentials.encode()).decode()
        headers['Authorization'] = f'Basic {encoded_credentials}'
    
    return headers

def get_image_key(image_name: str) -> str:
    """Extract key from image name for pattern matching"""
    clean_name = image_name.replace('ghcr.io/', '').replace('lscr.io/', '')
    clean_name = clean_name.replace('docker.io/', '').replace('quay.io/', '')
    
    if '/' in clean_name:
        parts = clean_name.split('/')
        return parts[-1].split(':')[0]
    return clean_name.split(':')[0]

def sanitize_for_github_env(content: str) -> str:
    """Sanitize content for GitHub Actions environment variables - much more aggressive"""
    if not content:
        return ""
    
    # Convert to string and handle encoding issues
    content = str(content)
    
    # Remove/replace problematic characters for GitHub Actions
    content = re.sub(r'[<>"`$\\]', '', content)  # Remove dangerous chars
    content = re.sub(r'[\r\n\t]', ' ', content)  # Replace newlines/tabs with spaces
    content = re.sub(r'\s+', ' ', content)       # Normalize whitespace
    content = re.sub(r'[^\x20-\x7E]', '', content)  # Remove non-printable chars
    
    # Limit length to prevent issues
    max_length = 200
    if len(content) > max_length:
        content = content[:max_length].rsplit(' ', 1)[0] + '...'
    
    return content.strip()

def get_ghcr_latest_tag(registry_path: str, rate_limiter: RateLimitManager) -> Optional[str]:
    """Get latest tag from GitHub Container Registry with authentication"""
    try:
        rate_limiter.wait_if_needed('ghcr')
        
        parts = registry_path.split('/')
        if len(parts) < 2:
            return None
        
        owner = parts[0]
        package = parts[1]
        
        # Use GitHub Packages API
        url = f"https://api.github.com/users/{owner}/packages/container/{package}/versions"
        headers = get_auth_headers()
        
        response = requests.get(url, headers=headers, timeout=20)
        
        if response.status_code == 429:
            print(f"Rate limited for GHCR {registry_path}, waiting...")
            time.sleep(60)
            return None
        
        if response.status_code != 200:
            print(f"GHCR API error for {registry_path}: {response.status_code}")
            return None
        
        versions = response.json()
        if not versions:
            return None
        
        # Find the latest version with a semantic version tag
        image_key = get_image_key(registry_path)
        pattern = VERSION_PATTERNS.get(image_key)
        
        for version in versions:
            tags = version.get('metadata', {}).get('container', {}).get('tags', [])
            for tag in tags:
                if pattern and re.match(pattern, tag):
                    return tag
                elif re.match(r'^\d+\.\d+(\.\d+)?$', tag):
                    return tag
                elif re.match(r'^v\d+\.\d+(\.\d+)?$', tag):
                    return tag
        
        return None
        
    except Exception as e:
        print(f"Error checking GHCR {registry_path}: {e}")
        return None

def get_latest_docker_tag(image_name: str, rate_limiter: RateLimitManager) -> Optional[str]:
    """Get the latest tag for a Docker image with enhanced authentication"""
    try:
        # Handle different registry formats
        if image_name.startswith('ghcr.io/'):
            registry_path = image_name.replace('ghcr.io/', '')
            return get_ghcr_latest_tag(registry_path, rate_limiter)
        elif image_name.startswith('lscr.io/'):
            # LinuxServer.io images - try fallback to GitHub releases
            registry_path = image_name.replace('lscr.io/', '')
            return get_dockerhub_latest_tag(registry_path, rate_limiter)
        elif '/' not in image_name:
            registry_path = f"library/{image_name}"
            return get_dockerhub_latest_tag(registry_path, rate_limiter)
        else:
            return get_dockerhub_latest_tag(image_name, rate_limiter)
        
    except Exception as e:
        print(f"Error checking {image_name}: {e}")
        return None

def get_dockerhub_latest_tag(registry_path: str, rate_limiter: RateLimitManager) -> Optional[str]:
    """Get latest tag with proper semantic version comparison"""
    try:
        rate_limiter.wait_if_needed('dockerhub')
        
        url = f"https://registry.hub.docker.com/v2/repositories/{registry_path}/tags"
        params = {"page_size": 100}  # Increased from 50, removed ordering
        headers = get_docker_hub_auth_headers()
        
        response = requests.get(url, params=params, headers=headers, timeout=20)
        
        if response.status_code == 429:
            print(f"Docker Hub rate limited for {registry_path}")
            time.sleep(30)
            return None
        
        if response.status_code != 200:
            print(f"Docker Hub API error for {registry_path}: {response.status_code}")
            return None
        
        data = response.json()
        tags = data.get("results", [])
        
        if not tags:
            return None
        
        image_key = get_image_key(registry_path)
        pattern = VERSION_PATTERNS.get(image_key)
        
        # Collect ALL valid version tags
        valid_tags = []
        
        # Try pattern matching first
        if pattern:
            for tag in tags:
                tag_name = tag["name"]
                if re.match(pattern, tag_name):
                    valid_tags.append(tag_name)
        
        # Fallback to generic semantic versioning
        if not valid_tags:
            for tag in tags:
                tag_name = tag["name"]
                if re.match(r'^\d+\.\d+(\.\d+)?$', tag_name):
                    valid_tags.append(tag_name)
                elif re.match(r'^v\d+\.\d+(\.\d+)?$', tag_name):
                    valid_tags.append(tag_name)
        
        if not valid_tags:
            return None
        
        # Find the HIGHEST version, not just the first one
        try:
            # Sort by semantic version (highest first)
            sorted_tags = sorted(valid_tags, key=lambda x: version.parse(clean_version(x)), reverse=True)
            return sorted_tags[0]
        except Exception as e:
            print(f"Error sorting versions for {registry_path}: {e}")
            return valid_tags[0]
        
    except Exception as e:
        print(f"Error checking Docker Hub {registry_path}: {e}")
        return None

def get_github_releases(repo_name: str, old_version: str, new_version: str, rate_limiter: RateLimitManager) -> Optional[List[Dict]]:
    """Get GitHub releases between two versions with enhanced error handling"""
    try:
        rate_limiter.wait_if_needed('github_api')
        
        url = f"https://api.github.com/repos/{repo_name}/releases"
        headers = get_auth_headers()
        response = requests.get(url, headers=headers, timeout=20)
        
        if response.status_code == 429:
            print(f"GitHub API rate limited for {repo_name}")
            time.sleep(60)
            return None
        
        if response.status_code != 200:
            return None
        
        releases = response.json()
        changes = []
        
        old_clean = old_version.replace('release-', '').replace('v', '').replace('-alpine', '')
        new_clean = new_version.replace('release-', '').replace('v', '').replace('-alpine', '')
        
        for release in releases:
            try:
                tag = release.get('tag_name', '').replace('release-', '').replace('v', '').replace('-alpine', '')
                
                if tag == new_clean or (old_clean < tag <= new_clean):
                    # Sanitize all text content for GitHub Actions safety
                    version = sanitize_for_github_env(release.get('tag_name', ''))
                    name = sanitize_for_github_env(release.get('name', ''))
                    body = sanitize_for_github_env(release.get('body', ''))
                    url = release.get('html_url', '')  # URLs are generally safe
                    published = release.get('published_at', '')[:10]  # Just the date part
                    
                    # Only add if we have meaningful content
                    if version and name:
                        changes.append({
                            'version': version,
                            'name': name,
                            'body': body,
                            'url': url,
                            'published': published
                        })
            except Exception as e:
                # Skip individual releases that cause issues
                print(f"Warning: Skipping release due to parsing error: {e}")
                continue
        
        return changes[:3]  # Limit to 3 most recent
        
    except Exception as e:
        print(f"Error getting releases for {repo_name}: {e}")
    return None

def check_service_for_updates(compose_file_path: str, rate_limiter: RateLimitManager) -> Tuple[List[Dict], bool]:
    """Check a specific docker-compose file for updates with rate limiting"""
    updates = []

    if "github-runner" in compose_file_path or "automation/github-runner" in compose_file_path:
        print(f"🚫 SKIPPING: {compose_file_path} (GitHub runner - never update during CI/CD)")
        return updates, False
    
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
        
        # Get latest version with rate limiting
        latest_tag = get_latest_docker_tag(image_name, rate_limiter)
        
        if latest_tag and compare_versions(current_tag, latest_tag):
            print(f"  Update available: {current_tag} -> {latest_tag}")
            
            # Get changelog if we have repo mapping
            changelog = None
            repo_name = REPO_MAPPINGS.get(image_name)
            if repo_name:
                changelog = get_github_releases(repo_name, current_tag, latest_tag, rate_limiter)
            
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
                print(f"  Up to date or downgrade rejected: {current_tag} >= {latest_tag}")
            else:
                print(f"  Could not check: {current_tag}")
    
    # Save modified file
    if modified:
        try:
            with open(compose_file_path, 'w') as f:
                yaml.dump(compose_data, f, default_flow_style=False, sort_keys=False)
        except Exception as e:
            print(f"Error writing {compose_file_path}: {e}")
            return updates, False
    
    return updates, modified

def safe_write_github_env(env_file: str, updates: List[Dict]) -> None:
    """Write environment variables for GitHub Actions using simple format"""
    try:
        with open(env_file, 'a') as f:
            f.write("UPDATES_FOUND=true\n")
            f.write(f"UPDATE_DATE={datetime.now().strftime('%Y-%m-%d')}\n")
            
            # Create a simple, safe summary
            summary_lines = []
            
            # Group by category
            by_category = {}
            for update in updates:
                category = update['file'].split('/')[1]
                if category not in by_category:
                    by_category[category] = []
                by_category[category].append(update)
            
            # Build summary
            summary_lines.append(f"Found {len(updates)} container updates across {len(by_category)} categories")
            summary_lines.append("")
            
            for category, cat_updates in sorted(by_category.items()):
                summary_lines.append(f"{category.upper()}:")
                for update in cat_updates:
                    service_name = sanitize_for_github_env(update['service'])
                    old_version = sanitize_for_github_env(update['old_version'])
                    new_version = sanitize_for_github_env(update['new_version'])
                    summary_lines.append(f"  - {service_name}: {old_version} -> {new_version}")
                summary_lines.append("")
            
            # Write as a simple string (no heredoc)
            summary_content = " | ".join(summary_lines).replace('\n', ' ')
            f.write(f"UPDATE_SUMMARY={summary_content}\n")
            
    except Exception as e:
        print(f"Error writing GitHub environment variables: {e}")
        # Fallback to absolute minimum
        with open(env_file, 'a') as f:
            f.write("UPDATES_FOUND=true\n")
            f.write(f"UPDATE_DATE={datetime.now().strftime('%Y-%m-%d')}\n")
            f.write(f"UPDATE_SUMMARY=Found {len(updates)} container updates\n")

def main():
    """Main function with enhanced rate limiting and authentication"""
    print("🔍 Enhanced Docker Update Checker with Authentication")
    print("=" * 60)
    
    # Check for authentication
    github_token = os.environ.get('GITHUB_TOKEN') or os.environ.get('GITHUB_ACCESS_TOKEN')
    docker_user = os.environ.get('DOCKER_HUB_USERNAME')
    
    print(f"GitHub Token: {'✅ Available' if github_token else '❌ Not set'}")
    print(f"Docker Hub Auth: {'✅ Available' if docker_user else '❌ Not set'}")
    print()
    
    if not github_token:
        print("⚠️ Warning: No GitHub token found. GHCR checks will be limited.")
        print("   Set GITHUB_TOKEN or GITHUB_ACCESS_TOKEN environment variable")
    
    if not docker_user:
        print("⚠️ Warning: No Docker Hub credentials. Rate limits will be strict.")
        print("   Set DOCKER_HUB_USERNAME and DOCKER_HUB_PASSWORD environment variables")
    
    print()
    
    rate_limiter = RateLimitManager()
    all_updates = []
    
    # Define paths
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        COMPOSE_BASE_PATH = '/workspace'
    else:
        COMPOSE_BASE_PATH = '/mnt/user/appdata/docker-compose'
    
    if os.path.exists(COMPOSE_BASE_PATH):
        os.chdir(COMPOSE_BASE_PATH)
        compose_files = glob.glob('services/**/docker-compose.yml', recursive=True)
    else:
        compose_files = glob.glob('services/**/docker-compose.yml', recursive=True)
    
    print(f"🔍 Checking {len(compose_files)} services for updates...")
    print(f"📁 Base path: {os.getcwd()}")
    print("=" * 60)
    
    for compose_file in sorted(compose_files):
        category = compose_file.split('/')[1] if len(compose_file.split('/')) > 1 else 'unknown'
        service = compose_file.split('/')[2] if len(compose_file.split('/')) > 2 else 'unknown'
        
        print(f"\n📁 {category}/{service}")
        print(f"   File: {compose_file}")
        
        updates, modified = check_service_for_updates(compose_file, rate_limiter)
        if updates:
            all_updates.extend(updates)
            print(f"   ✅ {len(updates)} update(s) found")
        else:
            print(f"   ℹ️ No updates available")
    
    print("\n" + "=" * 60)
    
    # Generate results with safe GitHub Actions handling
    if all_updates:
        env_file = os.environ.get('GITHUB_ENV', '/tmp/github_env')
        safe_write_github_env(env_file, all_updates)
        
        print(f"✅ Found {len(all_updates)} total updates!")
        
        # Group by category for console display
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
    
    print(f"\n✅ Update check completed successfully")

if __name__ == "__main__":
    main()
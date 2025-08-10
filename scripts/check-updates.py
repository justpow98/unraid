#!/usr/bin/env python3
import os
import yaml
import requests
import re
from datetime import datetime
import glob

# JP's Custom Container Repository Mappings
REPO_MAPPINGS = {
    'lissy93/dashy': 'lissy93/dashy',
    'filebrowser/filebrowser': 'filebrowser/filebrowser', 
    'xavierh/goaccess-for-nginxproxymanager': 'xavier-hernandez/goaccess-for-nginxproxymanager'
}

def get_latest_docker_tag(image_name):
    """Get the latest tag for a Docker image."""
    try:
        if '/' not in image_name:
            image_name = f"library/{image_name}"
        
        url = f"https://registry.hub.docker.com/v2/repositories/{image_name}/tags"
        params = {"page_size": 50, "ordering": "last_updated"}
        response = requests.get(url, timeout=10)
        
        if response.status_code == 200:
            tags = response.json()["results"]
            
            # Handle different tag formats
            if 'dashy' in image_name:
                # Look for release-X.X.X format
                for tag in tags:
                    tag_name = tag["name"]
                    if re.match(r'^release-\d+\.\d+\.\d+$', tag_name):
                        return tag_name
            elif 'filebrowser' in image_name:
                # Look for vX.X.X format
                for tag in tags:
                    tag_name = tag["name"]
                    if re.match(r'^v\d+\.\d+\.\d+$', tag_name):
                        return tag_name
            else:
                # Generic semantic version
                for tag in tags:
                    tag_name = tag["name"]
                    if re.match(r'^\d+\.\d+(\.\d+)?$', tag_name):
                        return tag_name
        
        return None
    except Exception as e:
        print(f"Error checking {image_name}: {e}")
        return None

def get_github_releases(repo_name, old_version, new_version):
    """Get GitHub releases between two versions."""
    try:
        url = f"https://api.github.com/repos/{repo_name}/releases"
        response = requests.get(url, timeout=10)
        
        if response.status_code == 200:
            releases = response.json()
            changes = []
            
            # Clean version strings for comparison
            old_clean = old_version.replace('release-', '').replace('v', '')
            new_clean = new_version.replace('release-', '').replace('v', '')
            
            for release in releases:
                tag = release.get('tag_name', '').replace('release-', '').replace('v', '')
                
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

def check_service_for_updates(compose_file_path):
    """Check a specific docker-compose file for updates."""
    updates = []
    
    with open(compose_file_path, 'r') as f:
        compose_data = yaml.safe_load(f)
    
    if 'services' not in compose_data:
        return updates, False
    
    modified = False
    
    for service_name, service_config in compose_data['services'].items():
        if 'image' not in service_config:
            continue
            
        current_image = service_config['image']
        
        # Skip latest tags
        if current_image.endswith(':latest'):
            continue
        
        # Parse image name and tag
        if ':' in current_image:
            image_name, current_tag = current_image.rsplit(':', 1)
        else:
            continue
        
        # Get latest version
        latest_tag = get_latest_docker_tag(image_name)
        
        if latest_tag and latest_tag != current_tag:
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
    
    # Save modified file
    if modified:
        with open(compose_file_path, 'w') as f:
            yaml.dump(compose_data, f, default_flow_style=False, sort_keys=False)
    
    return updates, modified

def main():
    """Main function to check all services for updates."""
    all_updates = []
    
    # Find all docker-compose.yml files
    compose_files = glob.glob('services/**/docker-compose.yml', recursive=True)
    
    print(f"Checking {len(compose_files)} services for updates...")
    
    for compose_file in compose_files:
        print(f"Checking {compose_file}...")
        updates, modified = check_service_for_updates(compose_file)
        if updates:
            all_updates.extend(updates)
    
    # Generate PR summary
    if all_updates:
        summary = "## 📋 Updated Services\\n\\n"
        
        for update in all_updates:
            summary += f"### 🔄 {update['service']} ({update['old_version']} → {update['new_version']})\\n"
            summary += f"**Image**: `{update['image']}`\\n"
            summary += f"**Repository**: [{update['repo']}](https://github.com/{update['repo']})\\n\\n" if update['repo'] else "\\n"
            
            if update['changelog']:
                summary += "**Recent Changes**:\\n"
                for change in update['changelog']:
                    summary += f"- **{change['version']}** ({change['published']}): {change['name']}\\n"
                    if change['body']:
                        summary += f"  {change['body']}\\n"
                    summary += f"  [View Release]({change['url']})\\n"
            else:
                summary += "**Changelog**: Check repository releases manually\\n"
            summary += "\\n---\\n\\n"
        
        # Set GitHub Actions environment variables
        env_file = os.environ.get('GITHUB_ENV', '/tmp/github_env')
        with open(env_file, 'a') as f:
            f.write("UPDATES_FOUND=true\n")
            f.write(f"UPDATE_DATE={datetime.now().strftime('%Y-%m-%d')}\n")
            f.write(f"UPDATE_SUMMARY={summary}\n")
        
        print(f"✅ Found {len(all_updates)} updates!")
        for update in all_updates:
            print(f"  - {update['service']}: {update['old_version']} → {update['new_version']}")
    else:
        env_file = os.environ.get('GITHUB_ENV', '/tmp/github_env')
        with open(env_file, 'a') as f:
            f.write("UPDATES_FOUND=false\n")
        print("ℹ️ All services are up to date!")

if __name__ == "__main__":
    main()

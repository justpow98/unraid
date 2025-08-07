# Unraid Docker Compose Configurations

Automated Docker Compose management system for my Unraid server with GitHub Actions integration.

## 🚀 Features

- **Automated Updates**: Weekly checks for container image updates
- **Pull Request Workflow**: Review changes before deployment
- **Automated Deployment**: Deploy to Unraid server after PR approval
- **Rollback Support**: Git history for easy rollbacks
- **Centralized Management**: All container configs in one place

## 📁 Repository Structure
.
├── .github/
│   └── workflows/          # GitHub Actions workflows
├── services/
│   ├── plex/              # Plex Media Server
│   ├── sonarr/            # TV Show management
│   ├── radarr/            # Movie management
│   ├── prowlarr/          # Indexer management
│   ├── qbittorrent/       # Torrent client
│   ├── overseerr/         # Request management
│   └── ...                # Other services
├── scripts/               # Automation scripts
└── docs/                  # Documentation
## 🛠️ Services

| Service | Purpose | Web UI Port |
|---------|---------|-------------|
| Plex | Media Server | 32400 |
| Sonarr | TV Show Management | 8989 |
| Radarr | Movie Management | 7878 |
| Prowlarr | Indexer Management | 9696 |
| qBittorrent | Torrent Client | 8080 |
| Overseerr | Request Management | 5055 |

## 🔧 Local Development

### Prerequisites
- Docker and Docker Compose installed
- Git configured with SSH keys

### Clone and Run
```bash
git clone git@github.com:yourusername/docker-compose-configs.git
cd docker-compose-configs

# Start a specific service
cd services/plex
docker-compose up -d

# Start all services (from root)
find services -name "docker-compose.yml" -execdir docker-compose up -d \;
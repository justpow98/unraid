# JP's Docker Compose Configurations

Automated Docker Compose management for my Unraid server with 35+ containers.

## 🚀 Features

- **Predictable Version Management**: Pinned versions instead of `:latest`
- **Organized Structure**: Services grouped by category
- **Git-Based Tracking**: All changes tracked and reversible
- **Ready for Automation**: Foundation for automated updates

## 📁 Repository Structure
services/
├── utilities/
│   ├── dashy/              # Service dashboard
│   └── filebrowser/        # File management
├── monitoring/             # Future: Grafana, Prometheus, UptimeKuma
├── iot/                   # Future: Home Assistant, Zigbee2MQTT
├── productivity/          # Future: Nextcloud, Actual, WikiJS
└── critical/              # Future: Authentik, Vaultwarden, NPM

## 🎯 Migration Status

| Service | Status | Version | Migration Date | Notes |
|---------|--------|---------|----------------|-------|
| **Utilities** |
| Dashy | ✅ Complete | release-3.1.1 | 2025-08-09 | Perfect migration, dashboard working |
| FileBrowser | ✅ Complete | v2.42.3 | 2025-08-10 | File access preserved, privileged mode working |
| **Next Targets** |
| GoAccess-NPMLogs | ⏳ Planned | - | - | Log viewer utility |
| UptimeKuma + AutoKuma | ⏳ Planned | - | - | First services with dependencies |
| **Future Phases** |
| Monitoring Stack | 📋 Future | - | - | Grafana, Prometheus, exporters |
| Smart Home | 📋 Future | - | - | Home Assistant, Zigbee2MQTT, mosquitto |
| Critical Apps | 📋 Future | - | - | Authentik, Vaultwarden, NPM |
| Databases | 📋 Future | - | - | All PostgreSQL, Redis, MongoDB (LAST) |

## 🛠️ Usage

### Deploy a Service
```bash
cd services/utilities/dashy
docker-compose --env-file ../../../.env up -d# Workflow files for automation

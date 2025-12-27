# J3D - Etsy Orders & Filament Tracker

Production-ready 3D print shop management system for Etsy sellers. Manage orders, track filament inventory, control Bambu Lab printers, and analyze profitability.

## Features

- 📦 **Order Management** - Sync and track Etsy orders in real-time
- 🎨 **Filament Tracking** - Monitor inventory, costs, and usage
- 🖨️ **Bambu Connect** - Control printers, manage AMS materials
- 📊 **Analytics** - Revenue trends, profitability, product performance
- 🔐 **OAuth Authentication** - Secure Etsy OAuth integration
- 🚀 **Production Ready** - Multi-stage Docker builds, security hardening

## Version

**2.0.0** - Production Release

## Prerequisites

1. **Networks Created in Unraid**:
   ```bash
   docker network create internal_net
   docker network create public_net
   docker network create db_net
   ```

2. **Etsy App Credentials**:
   - Register app at [Etsy Developers](https://www.etsy.com/developers)
   - Get Client ID and Secret
   - Set redirect URI in Etsy dashboard

3. **Nginx Proxy Manager** (optional but recommended):
   - Expose frontend through custom domain
   - Automatic SSL/TLS certificates via Let's Encrypt

## Quick Start

### 1. Setup Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit with your values
nano .env
```

**Required values to set**:
- `POSTGRES_PASSWORD` - Strong database password
- `SECRET_KEY` - Generate: `python -c "import secrets; print(secrets.token_hex(32))"`
- `ETSY_CLIENT_ID` - From Etsy app
- `ETSY_CLIENT_SECRET` - From Etsy app
- `ETSY_REDIRECT_URI` - Your frontend URL with `/oauth-callback`

### 2. Start Services

```bash
# Deploy containers
docker-compose up -d

# Watch logs
docker-compose logs -f

# Verify health
docker-compose ps
```

### 3. Access Application

- **Frontend**: http://localhost:4200
- **Backend API**: http://localhost:5000/api
- **PostgreSQL**: localhost:5432

### 4. Create Admin User (via backend API)

```bash
# Login with Etsy OAuth - user created automatically
# Or use backend endpoints to create user
```

## Configuration

### Docker Compose Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TZ` | US/Eastern | Timezone |
| `PUID` / `PGID` | 99/100 | Unraid user/group |
| `J3D_VERSION` | 2.0.0 | Docker image version tag |
| `POSTGRES_PASSWORD` | changeme | ⚠️ CHANGE THIS |
| `SECRET_KEY` | (required) | Flask session key |
| `ETSY_CLIENT_ID` | (required) | OAuth app ID |
| `ETSY_CLIENT_SECRET` | (required) | OAuth app secret |
| `ETSY_REDIRECT_URI` | (required) | OAuth callback URL |

### Volumes

```
${APPDATA_PATH}/j3d/
├── postgres/
│   ├── data/          # PostgreSQL database files
│   └── backups/       # Database backups
├── backend/           # Backend instance files
├── uploads/           # File uploads
```

## Production Deployment

### 1. Enable HTTPS

Add Nginx Proxy Manager host:
- Domain: `j3d.yourdomain.com`
- Upstream: `j3d-frontend:4200`
- SSL: Enable Let's Encrypt

Update `.env`:
```bash
ETSY_REDIRECT_URI=https://j3d.yourdomain.com/oauth-callback
```

### 2. Database Backups

Create backup script in `/mnt/user/scripts/`:

```bash
#!/bin/bash
BACKUP_DIR="/mnt/user/appdata/j3d/postgres/backups"
mkdir -p "$BACKUP_DIR"

docker exec j3d-postgres pg_dump -U j3d_user j3d \
  | gzip > "$BACKUP_DIR/backup-$(date +%Y%m%d_%H%M%S).sql.gz"

# Keep only last 30 days
find "$BACKUP_DIR" -mtime +30 -delete
```

### 3. Monitoring

Containers include Uptime Kuma integration:
- Health checks enabled on all services
- Metrics available via prometheus (if using monitoring_net)
- Logs accessible via `docker-compose logs`

## Troubleshooting

### Backend won't start
```bash
# Check database connection
docker-compose logs j3d-backend

# Verify PostgreSQL is healthy
docker-compose ps postgres
```

### OAuth callback fails
- Verify `ETSY_REDIRECT_URI` matches Etsy app configuration
- Check frontend can reach backend (`/api` proxy working)
- Review backend logs for auth errors

### Database locked
```bash
# Reset database (⚠️ DESTRUCTIVE)
docker-compose down -v
docker-compose up -d
```

### Performance issues
- Check PostgreSQL log: `docker-compose logs postgres`
- Verify disk I/O on Unraid
- Increase PostgreSQL buffers if needed

## Maintenance

### Update Version

Edit `.env`:
```bash
J3D_VERSION=2.1.0  # or latest
```

Pull new image and restart:
```bash
docker-compose pull
docker-compose up -d
```

### Database Maintenance

```bash
# Run vacuum/analyze
docker exec j3d-postgres psql -U j3d_user -d j3d -c "VACUUM ANALYZE;"

# Check database size
docker exec j3d-postgres psql -U j3d_user -d j3d -c "\l+"
```

## Documentation

- **API Reference**: See [j3d-backend/docs/API.md](https://github.com/justpow98/j3d-backend/blob/main/docs/API.md)
- **Architecture**: See [j3d-backend/docs/ARCHITECTURE.md](https://github.com/justpow98/j3d-backend/blob/main/docs/ARCHITECTURE.md)
- **Bambu Lab Integration**: See [j3d-backend/docs/BAMBU_CONNECT_FEATURES.md](https://github.com/justpow98/j3d-backend/blob/main/docs/BAMBU_CONNECT_FEATURES.md)

## Security

- ✅ No hardcoded credentials
- ✅ Environment-based configuration
- ✅ HTTPS support
- ✅ OAuth authentication
- ✅ JWT token management
- ✅ SQL injection protected (SQLAlchemy)

## License

MIT License - See LICENSE file

## Support

For issues or questions:
- GitHub Issues: [j3d-frontend](https://github.com/justpow98/j3d-frontend/issues) / [j3d-backend](https://github.com/justpow98/j3d-backend/issues)
- Docker Hub: [justpow98](https://hub.docker.com/u/justpow98)

---

**Version**: 2.0.0  
**Last Updated**: December 2024

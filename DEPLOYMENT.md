# Production Deployment & Operations Guide

This guide details the steps to deploy FlowSpace to production environments, configure SSL security, and run database backups.

For local development steps, consult the **[Installation Guide](file:///c:/Users/Admin/Documents/mad2/docs/INSTALLATION.md)**. For database structure details, consult the **[Master Developer Handbook](file:///c:/Users/Admin/Documents/mad2/docs/PROJECT_HANDBOOK.md)**.

---

## 🐳 Docker Production Architecture

In production, FlowSpace runs as three main container services orchestrated via Docker Compose:

1. **`db` (PostgreSQL Database)**:
   * Runs PostgreSQL 16 on alpine.
   * Utilizes a persistent volume (`postgres_data`) mapping data states safely.
   * Includes liveness health checks verifying connection ready states.
2. **`backend` (FastAPI Web App)**:
   * Uses Gunicorn process manager running 4 worker nodes.
   * Connects to PostgreSQL database with startup verification loops.
   * Maps user assets (furniture glTFs, textures, thumbnails) to a persistent folder.
3. **`frontend` (Nginx gateway)**:
   * Serving static compiled Flutter Web files.
   * Reverse-proxies `/api/`, `/uploads/`, and `/static/` traffic back to the backend.
   * Terminates SSL and enforces production security headers.

---

## 🚀 Step-by-Step Deployment Procedure

### 1. Build and Run the Stack
From the workspace root directory, start the production containers in daemon mode:
```bash
docker-compose up --build -d
```

### 2. Verify Container Health
Check the container states and health statuses:
```bash
docker-compose ps
```
The console will display:
* `flowspace_postgres` -> `Up (healthy)`
* `flowspace_backend` -> `Up (healthy)`
* `flowspace_frontend` -> `Up (healthy)`

### 3. Database Migration Loops
Migrations are automatically applied by the backend container's entrypoint script (`entrypoint.sh`) before launching the web server.
To manually verify database statuses or run custom migrations inside the running container:
```bash
docker-compose exec backend alembic current
docker-compose exec backend alembic upgrade head
```

---

## 🔒 SSL & Nginx Configuration

### Production Security Headers
The production Nginx config ([nginx.prod.conf](file:///c:/Users/Admin/Documents/mad2/frontend/nginx.prod.conf)) enforces safety rules:
* Redirects all port 80 HTTP requests to HTTPS via 301.
* Enforces HTTP/2 multiplexing.
* Registers headers:
  ```nginx
  add_header X-Frame-Options "DENY" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
  ```

### Self-Signed Certificate Fallback
To ensure out-of-the-box startup, the frontend Dockerfile compiles a 365-day self-signed certificate during build.
**In Production**: Mount your actual SSL certificates (from Let's Encrypt or your CA) into the frontend container by updating the volume configuration in `docker-compose.yml`:
```yaml
frontend:
  volumes:
    - /etc/letsencrypt/live/yourdomain.com/fullchain.pem:/etc/nginx/ssl/nginx.crt:ro
    - /etc/letsencrypt/live/yourdomain.com/privkey.pem:/etc/nginx/ssl/nginx.key:ro
```

---

## ⚙️ Diagnostics, Logs, & Monitoring

### Viewing Logs
To inspect application logs in production:
```bash
# View backend logs:
docker-compose logs -f backend

# View Nginx access/error logs:
docker-compose logs -f frontend
```

### Health Probes
Cloud load balancers and orchestrators (e.g. Kubernetes, AWS ECS) can monitor container health using the following endpoints:
* **Liveness**: `GET http://localhost:8000/health/live` (Checks if backend is running).
* **Readiness**: `GET http://localhost:8000/health/ready` (Checks database connection and storage write permissions).

---

## 💾 Database Backup & Disaster Recovery

Backup scripts are provided in the `/scripts` directory to automatically back up database states:
* Linux shell script: [backup_db.sh](file:///c:/Users/Admin/Documents/mad2/scripts/backup_db.sh)
* Windows PowerShell script: [backup_db.ps1](file:///c:/Users/Admin/Documents/mad2/scripts/backup_db.ps1)

### Features:
* Connects directly to the PostgreSQL database container.
* Runs `pg_dump` and compresses the file with gzip.
* Saves backup archives with a datetime prefix.
* Automatically deletes backup archives older than 7 days to conserve disk space.

### Manually trigger backup (Linux):
```bash
cd scripts
chmod +x backup_db.sh
./backup_db.sh
```

### Manually trigger backup (Windows):
```powershell
cd scripts
.\backup_db.ps1
```

### Schedule Backups:
Use crontab on your host machine to run the backup script daily at 1:00 AM:
```cron
0 1 * * * /absolute/path/to/scripts/backup_db.sh >> /var/log/flowspace_backup.log 2>&1
```

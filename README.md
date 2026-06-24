# MCdesk One-Liner Installation

A single Bash script that installs the full **MCdesk** ITSM web application stack on Linux using Docker Compose.

## Components

- **MCdesk Backend** — Java Spring Boot (`mcdesk-backend`)
- **MCdesk Frontend** — Nginx + Vue.js (`mcdesk-frontend`)
- **PostgreSQL** — application database
- **Redis** — cache / session store
- **Kafka + Zookeeper** — message bus
- **Cloudflare Tunnel** — optional public HTTPS access

## Quick Start

Run the installer:

```bash
bash <(curl -fsSL https://your-distribution-url/install.sh)
```

Or clone this repository and run locally:

```bash
cd one-liner-installation
bash install.sh
```

## What the Script Does

1. Checks that Docker and Docker Compose are installed and running.
2. Prompts for configuration values with sensible defaults.
3. Generates a secure PostgreSQL password if not provided.
4. Copies/downloads `docker-compose.yml`, `mcdesk.env`, and `mcdesk-nginx.conf`.
5. Writes a local `.env` file with your settings.
6. Optionally logs in to `repo.magiccreative.ai`.
7. Pulls images and starts the stack.
8. Waits for the backend healthcheck and prints a summary.

## Interactive Prompts

| Setting | Default |
|---------|---------|
| Installation directory | `/opt/mcdesk` |
| Image tag | `20260624-51-qa-v2-0-1-29-5-70916dc48e` |
| Frontend port | `80` |
| Backend port | `7080` |
| PostgreSQL DB/user | `mcdesk` / `mcdesk` |
| Redis DB index | `0` |
| Docker network | `mcdesk-net` |
| Timezone | `Asia/Hong_Kong` |
| Database backup | *(optional)* |

## Database Backup Restore

The installer can optionally restore an existing PostgreSQL backup before starting the application. When prompted, provide the path to a `.sql` or `.sql.gz` backup file.

You can also set it via environment variable for non-interactive installs:

```bash
export MCDESK_DB_BACKUP=/path/to/mcdesk_backup.sql.gz
bash install.sh
```

> **Note:** The MCdesk application image may fail to start from a completely empty database due to Flyway migration script incompatibilities with PostgreSQL. For a working deployment, restore from a known-good backup.

## Non-Interactive / Automated Install

For CI/CD or unattended deployments, set `MCDESK_NONINTERACTIVE=1` and provide values via environment variables:

```bash
export MCDESK_NONINTERACTIVE=1
export INSTALL_DIR=/opt/mcdesk
export MCDESK_TAG=20260624-51-qa-v2-0-1-29-5-70916dc48e
export MCDESK_FRONTEND_PORT=80
export MCDESK_DB_PASSWORD=ChangeMe!
export MCDESK_DB_BACKUP=/path/to/backup.sql.gz
bash install.sh
```

## Cloudflare Tunnel

If you choose to enable the tunnel, you need a Cloudflare Tunnel token. The tunnel runs in an isolated Compose profile and is only started when requested.

To add a tunnel later:

```bash
cd /opt/mcdesk
# Add your token to .env, then:
docker compose --profile cloudflare up -d
```

## Access the Application

- **Local**: http://localhost (or the port you chose)
- **Public**: the URL shown in your Cloudflare Tunnel dashboard

Default credentials:

```
Username: admin
Password: 111111
```

## Management Commands

```bash
cd /opt/mcdesk

# View running services
docker compose ps

# View backend logs
docker compose logs -f mcdesk-backend

# Restart the stack
docker compose restart

# Stop the stack
docker compose down

# Stop and remove data volumes (destructive)
docker compose down -v
```

## Troubleshooting

- **Port 80 already in use**: choose a different frontend port during installation or stop the existing service.
- **Cannot pull images**: ensure you are logged in to `repo.magiccreative.ai` (`docker login repo.magiccreative.ai`).
- **Backend stays unhealthy**: check backend logs with `docker compose logs -f mcdesk-backend`.
  - If you see `Flyway migration failed` with NOT-NULL constraint errors, restore from a database backup instead of starting with an empty database.
- **Chinese full-text search features unavailable**: the default `postgres:16-alpine` image does not include the `zhparser` extension. This does not affect normal login or operation, but Chinese search features may be limited.
- **Cloudflare Tunnel not connecting**: verify the token in `.env` and check tunnel logs with `docker compose logs -f cloudflared`.

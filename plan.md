# MCdesk One-Liner Installation Plan

## 1. Goal

Create a Linux one-liner installation script that deploys the **MCdesk** ITSM web application stack using a single Docker Compose file, exposes the frontend on port **80**, and includes a **Cloudflare Tunnel** for public HTTPS access.

## 2. Stack Components

Based on `initial_prompt.md` and the reference deployments, the unified stack will contain:

| Component | Technology | Notes |
|-----------|-----------|-------|
| Backend | Java Spring Boot (`mcdesk-backend`) | Image from `repo.magiccreative.ai` |
| Frontend | Nginx + Vue.js (`mcdesk-frontend`) | Exposed on host port 80 |
| Database | PostgreSQL | Replaces external `10.247.36.38:5432` DB |
| Cache / MQ helper | Redis | Replaces external `10.247.36.38:6379` |
| Message Bus | Kafka (+ Zookeeper) | Replaces external `10.247.36.38:9092` |
| Public Access | Cloudflare Tunnel (`cloudflared`) | Provides `https://` endpoint without opening firewall |

> **Out of scope (not requested):** OpenSearch / MCWiki. If needed later, they can be added as optional services.

## 3. Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Host (Linux)                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                Docker Compose Network                │   │
│  │  ┌─────────────┐        ┌─────────────────────┐     │   │
│  │  │ cloudflared │───────▶│  mcdesk-frontend    │     │   │
│  │  │   (tunnel)  │        │  nginx :80          │     │   │
│  │  └─────────────┘        └──────────┬────────────┘     │   │
│  │                                    │                  │   │
│  │                         ┌──────────▼────────────┐     │   │
│  │                         │   mcdesk-backend      │     │   │
│  │                         │   Spring Boot :7080   │     │   │
│  │                         └──────────┬────────────┘     │   │
│  │                                    │                  │   │
│  │       ┌──────────┐    ┌───────────┼──────────┐       │   │
│  │       │  kafka   │◄───┤  postgres │  redis   │       │   │
│  │       │zookeeper │    │  :5432    │  :6379   │       │   │
│  │       └──────────┘    └───────────┴──────────┘       │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    https://<cloudflare-tunnel>
```

## 4. File Layout

```
one-liner-installation/
├── install.sh              # Main one-liner bootstrap script
├── docker-compose.yml      # Unified stack definition
├── mcdesk.env              # Backend runtime configuration
├── mcdesk-nginx.conf       # Nginx frontend config (Vue history mode)
├── README.md               # Usage / troubleshooting
└── plan.md                 # This document
```

## 5. Implementation Steps

### Step 1 — Gather Requirements & Defaults

Prompt the user during `install.sh` execution. Provide sensible defaults:

| Prompt | Default | Used In |
|--------|---------|---------|
| Installation directory | `/opt/mcdesk` | Working dir for compose |
| Docker network name | `mcdesk-net` | Compose service network |
| Frontend host port | `80` | `mcdesk-frontend` port mapping |
| Backend internal port | `7080` | `mcdesk-backend` SERVER_PORT |
| PostgreSQL database | `mcdesk` | DB name / user |
| PostgreSQL password | auto-generated | `postgres` service + backend env |
| Redis database index | `0` | Backend `REDIS_DB` |
| Kafka topic prefix | `mcdesk` | Optional Kafka env |
| Cloudflare Tunnel token | *(required, no default)* | `cloudflared` service |
| Image tag (`MCDESK_TAG`) | `20260624-51-qa-v2-0-1-29-5-70916dc48e` | Backend & frontend images |
| Timezone | `Asia/Hong_Kong` | All containers |

### Step 2 — Build `docker-compose.yml`

Combine all services into a single Compose project. Key decisions:

- **Use a Docker bridge network** (not `network_mode: host`) so services can resolve each other by service name.
- **PostgreSQL**, **Redis**, **Zookeeper**, and **Kafka** run as containers.
- **Backend** connects to DB/Redis/Kafka via internal hostnames (`postgres`, `redis`, `kafka:9092`).
- **Frontend** proxies API requests to `http://mcdesk-backend:7080` and serves Vue.js on port `80`.
- **Cloudflare Tunnel** points to `http://mcdesk-frontend:80`.
- Add `depends_on` with `service_healthy` or `service_started` where supported.
- Add `healthcheck` blocks for backend, frontend, postgres, redis, and kafka.

### Step 3 — Build `mcdesk.env`

Derived from the reference `/home/pine/.../mcdesk.env`, but updated for containerized dependencies:

- `DB_URL=jdbc:postgresql://postgres:5432/mcdesk`
- `REDIS_SINGLE_HOST=redis`
- `KAFKA_BOOTSTRAP_SERVERS=kafka:9092`
- Remove hard-coded external IPs.
- Keep other application settings (pool sizes, Kafka tuning, file storage, etc.) aligned with the reference.
- Secrets (`DB_PASSWORD`) injected via environment variables generated by `install.sh`, not hard-coded.

### Step 4 — Build `mcdesk-nginx.conf`

A minimal Nginx config for the Vue.js SPA:

- Listen on port `80`.
- Serve static files from the container's default path (e.g., `/usr/share/nginx/html`).
- Proxy `/api/` and `/actuator/` paths to `mcdesk-backend:7080`.
- Fallback to `index.html` for Vue Router history mode.

### Step 5 — Build `install.sh`

A single Bash script that the user can run with:

```bash
curl -fsSL https://<your-distribution-url>/install.sh | sudo bash
```

Responsibilities:

1. Check Linux OS, root/sudo, and installed dependencies (`docker`, `docker compose`).
2. Prompt for configuration values with defaults.
3. Generate a secure PostgreSQL password if not provided.
4. Create the installation directory and download `docker-compose.yml`, `mcdesk.env`, and `mcdesk-nginx.conf`.
5. Write a local `.env` file with user inputs and secrets.
6. Login to `repo.magiccreative.ai` if credentials are required (prompt or detect existing `~/.docker/config.json`).
7. Pull images and start the stack: `docker compose up -d`.
8. Wait for healthchecks and print a summary (local URL, Cloudflare public URL, logs command).

### Step 6 — Testing & Validation

After implementation, verify:

- `docker compose ps` shows all services healthy.
- `curl http://localhost` returns the frontend.
- `curl http://localhost/api/actuator/health` (or configured health path) returns backend healthy.
- PostgreSQL, Redis, and Kafka are reachable from the backend container.
- Cloudflare Tunnel status shows `Healthy` and the public URL loads the application.

### Step 7 — Documentation

Create `README.md` covering:

- One-liner command.
- Prerequisites (Linux, Docker, Docker Compose plugin, internet access).
- Interactive prompts and defaults.
- How to update the image tag and redeploy.
- How to view logs and troubleshoot.
- How to remove the stack.

## 6. Security Considerations

- Do **not** commit secrets to Git. `mcdesk.env` should contain only non-secret defaults; runtime secrets live in the generated `.env`.
- Use `secrets:` or environment variables for PostgreSQL credentials.
- Cloudflare Tunnel token is passed as an environment variable at runtime.
- Optionally restrict PostgreSQL and Redis to the internal Docker network (no host exposure).
- Frontend only needs port `80` exposed to the host; Cloudflare Tunnel connects internally.

## 7. Deliverables

1. `install.sh` — production-ready one-liner bootstrap.
2. `docker-compose.yml` — unified stack.
3. `mcdesk.env` — backend application configuration.
4. `mcdesk-nginx.conf` — frontend reverse proxy / SPA config.
5. `README.md` — user and operator documentation.
6. `plan.md` — this plan.

## 8. Next Action

Proceed to implement the files listed in **Deliverables** using the architecture and defaults above.

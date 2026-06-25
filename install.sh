#!/usr/bin/env bash
# =============================================================================
# MCdesk One-Liner Installation Script
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_INSTALL_DIR="/opt/mcdesk"
DEFAULT_TAG="20260624-52-feature-dev-ITSM-DPO-4ead84075d"
DEFAULT_FRONTEND_PORT="80"
DEFAULT_BACKEND_PORT="7080"
DEFAULT_DB_NAME="mcdesk"
DEFAULT_DB_USER="mcdesk"
DEFAULT_REDIS_DB="0"
DEFAULT_REDIS_KEY_PREFIX="mcdesk"
DEFAULT_NETWORK_NAME="mcdesk-net"
DEFAULT_TZ="Asia/Hong_Kong"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log_info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

require_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "Required command '$1' is not installed. Please install it first."
        exit 1
    fi
}

generate_password() {
    # Disable pipefail locally; otherwise head closing the pipe early can make
    # tr exit with SIGPIPE and abort the whole script.
    set +o pipefail
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
}

prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="${3:-}"
    local is_secret="${4:-false}"

    # In non-interactive mode, use the current value or default without asking.
    local current_value
    current_value="${!var_name:-}"
    if [[ "${MCDESK_NONINTERACTIVE:-}" == "1" ]]; then
        if [[ -n "$current_value" ]]; then
            printf -v "$var_name" '%s' "$current_value"
        else
            printf -v "$var_name" '%s' "$default_value"
        fi
        return
    fi

    if [[ "$is_secret" == "true" ]]; then
        if [[ -n "$default_value" ]]; then
            read -rsp "$prompt_text [$default_value]: " value || true
        else
            read -rsp "$prompt_text: " value || true
        fi
        echo "" >&2
    else
        if [[ -n "$default_value" ]]; then
            read -rp "$prompt_text [$default_value]: " value || true
        else
            read -rp "$prompt_text: " value || true
        fi
    fi

    if [[ -z "$value" && -n "$default_value" ]]; then
        value="$default_value"
    fi
    printf -v "$var_name" '%s' "$value"
}

prompt_yn() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="${3:-N}"

    if [[ "${MCDESK_NONINTERACTIVE:-}" == "1" ]]; then
        printf -v "$var_name" '%s' "$default_value"
        return
    fi

    read -rp "$prompt_text [y/N]: " value || true
    value="${value:-$default_value}"
    printf -v "$var_name" '%s' "${value,,}"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
log_info "Checking prerequisites..."
require_command docker
require_command curl

if ! docker info &>/dev/null; then
    log_error "Docker daemon is not running or current user cannot access Docker."
    log_error "Please start Docker or add the current user to the 'docker' group."
    exit 1
fi

if ! docker compose version &>/dev/null && ! docker-compose version &>/dev/null; then
    log_error "Docker Compose plugin is not installed."
    exit 1
fi

COMPOSE_CMD="docker compose"
if ! docker compose version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
fi

# ---------------------------------------------------------------------------
# Interactive configuration
# ---------------------------------------------------------------------------
log_info "Please provide the installation parameters (press Enter to accept defaults):"
echo ""

# Values may be pre-set via environment variables (useful for CI/CD or testing).
INSTALL_DIR="${INSTALL_DIR:-}"
MCDESK_TAG="${MCDESK_TAG:-}"
FRONTEND_PORT="${MCDESK_FRONTEND_PORT:-}"
BACKEND_PORT="${MCDESK_BACKEND_PORT:-}"
DB_NAME="${MCDESK_DB_NAME:-}"
DB_USER="${MCDESK_DB_USER:-}"
DB_PASSWORD="${MCDESK_DB_PASSWORD:-}"
REDIS_DB="${MCDESK_REDIS_DB:-}"
REDIS_KEY_PREFIX="${MCDESK_REDIS_KEY_PREFIX:-}"
NETWORK_NAME="${MCDESK_NETWORK_NAME:-}"
TZ="${TZ:-}"
ENABLE_CLOUDFLARE="${ENABLE_CLOUDFLARE:-}"
CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"
DB_BACKUP_FILE="${MCDESK_DB_BACKUP:-}"

prompt INSTALL_DIR      "Installation directory"        "$DEFAULT_INSTALL_DIR"
prompt MCDESK_TAG       "MCdesk image tag"              "$DEFAULT_TAG"
prompt FRONTEND_PORT    "Frontend HTTP port"            "$DEFAULT_FRONTEND_PORT"
prompt BACKEND_PORT     "Backend internal port"         "$DEFAULT_BACKEND_PORT"
prompt DB_NAME          "PostgreSQL database name"      "$DEFAULT_DB_NAME"
prompt DB_USER          "PostgreSQL username"           "$DEFAULT_DB_USER"
prompt DB_PASSWORD      "PostgreSQL password (auto if empty)" "" true
prompt REDIS_DB         "Redis database index"          "$DEFAULT_REDIS_DB"
prompt REDIS_KEY_PREFIX "Redis key prefix"              "$DEFAULT_REDIS_KEY_PREFIX"
prompt NETWORK_NAME     "Docker network name"           "$DEFAULT_NETWORK_NAME"
prompt TZ               "Container timezone"            "$DEFAULT_TZ"
prompt DB_BACKUP_FILE   "Path to PostgreSQL backup to restore (optional)" ""

if [[ -n "$DB_BACKUP_FILE" && ! -f "$DB_BACKUP_FILE" ]]; then
    log_error "Database backup file not found: $DB_BACKUP_FILE"
    exit 1
fi

if [[ -z "$DB_PASSWORD" ]]; then
    DB_PASSWORD="$(generate_password)"
    log_info "Generated PostgreSQL password: $DB_PASSWORD"
fi

# Default to enabling the tunnel when a token is already supplied.
DEFAULT_ENABLE_CLOUDFLARE="N"
[[ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]] && DEFAULT_ENABLE_CLOUDFLARE="Y"

prompt_yn ENABLE_CLOUDFLARE "Enable Cloudflare Tunnel public access?" "$DEFAULT_ENABLE_CLOUDFLARE"

if [[ "$ENABLE_CLOUDFLARE" == "y" || "$ENABLE_CLOUDFLARE" == "yes" ]]; then
    if [[ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]]; then
        prompt CLOUDFLARE_TUNNEL_TOKEN "Cloudflare Tunnel token" "" true
    fi
    if [[ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]]; then
        log_error "Cloudflare Tunnel token is required when tunnel is enabled."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Prepare installation directory
# ---------------------------------------------------------------------------
log_info "Installing MCdesk to: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
INSTALL_DIR="$(pwd)"

# Copy bundled assets if running from the same repository,
# otherwise download from the distribution URL.
if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    log_info "Using bundled compose files from $SCRIPT_DIR"
    cp -f "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/"
    cp -f "$SCRIPT_DIR/mcdesk.env" "$INSTALL_DIR/"
    cp -f "$SCRIPT_DIR/mcdesk-nginx.conf" "$INSTALL_DIR/"
    if [[ -f "$SCRIPT_DIR/sql/init_zhparser.sql" ]]; then
        mkdir -p "$INSTALL_DIR/sql"
        cp -f "$SCRIPT_DIR/sql/init_zhparser.sql" "$INSTALL_DIR/sql/"
    fi
else
    log_info "Downloading compose files..."
    curl -fsSL -o docker-compose.yml  "https://raw.githubusercontent.com/magiccreative/one-liner-installation/main/docker-compose.yml"
    curl -fsSL -o mcdesk.env          "https://raw.githubusercontent.com/magiccreative/one-liner-installation/main/mcdesk.env"
    curl -fsSL -o mcdesk-nginx.conf   "https://raw.githubusercontent.com/magiccreative/one-liner-installation/main/mcdesk-nginx.conf"
    mkdir -p "$INSTALL_DIR/sql"
    curl -fsSL -o "$INSTALL_DIR/sql/init_zhparser.sql" "https://raw.githubusercontent.com/magiccreative/one-liner-installation/main/sql/init_zhparser.sql"
fi

# ---------------------------------------------------------------------------
# Write runtime environment file
# ---------------------------------------------------------------------------
cat > "$INSTALL_DIR/.env" <<EOF
MCDESK_TAG=${MCDESK_TAG}
MCDESK_FRONTEND_PORT=${FRONTEND_PORT}
MCDESK_BACKEND_PORT=${BACKEND_PORT}
MCDESK_DB_NAME=${DB_NAME}
MCDESK_DB_USER=${DB_USER}
MCDESK_DB_PASSWORD=${DB_PASSWORD}
MCDESK_REDIS_DB=${REDIS_DB}
MCDESK_REDIS_KEY_PREFIX=${REDIS_KEY_PREFIX}
MCDESK_REDIS_PASSWORD=${MCDESK_REDIS_PASSWORD:-}
MCDESK_NETWORK_NAME=${NETWORK_NAME}
TZ=${TZ}
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
EOF

chmod 600 "$INSTALL_DIR/.env"

# ---------------------------------------------------------------------------
# Registry login check
# ---------------------------------------------------------------------------
if ! grep -q '"repo.magiccreative.ai"' "$HOME/.docker/config.json" 2>/dev/null; then
    log_warn "No Docker login found for repo.magiccreative.ai."
    log_warn "Please run: docker login repo.magiccreative.ai"
    if [[ "${MCDESK_NONINTERACTIVE:-}" != "1" ]]; then
        read -rsp "Docker registry password (press Enter to skip if already logged in): " reg_password || true
        echo "" >&2
        if [[ -n "$reg_password" ]]; then
            read -rp "Docker registry username: " reg_username || true
            echo "$reg_password" | docker login repo.magiccreative.ai -u "$reg_username" --password-stdin
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Pull and start services
# ---------------------------------------------------------------------------
log_info "Pulling images..."
$COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" pull

log_info "Starting PostgreSQL..."
$COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" up -d postgres

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" exec -T postgres pg_isready -U "${DB_USER}" -d "${DB_NAME}" &>/dev/null; then
        log_info "PostgreSQL is ready."
        break
    fi
    sleep 1
done

# The bitnami PostgreSQL container creates the application database
# asynchronously after the daemon starts. Wait until it actually exists.
log_info "Waiting for MCdesk database '${DB_NAME}' to be created..."
for i in {1..30}; do
    if $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" exec -T -e PGPASSWORD="${DB_PASSWORD}" postgres psql -U postgres -d "${DB_NAME}" -c "SELECT 1" &>/dev/null; then
        log_info "MCdesk database is ready."
        break
    fi
    sleep 1
done

# MCdesk Flyway migrations require the zhparser PostgreSQL extension.
# It must be installed by a superuser before the backend starts.
ZHPARSER_SQL="$INSTALL_DIR/sql/init_zhparser.sql"
if [[ -f "$ZHPARSER_SQL" ]]; then
    log_info "Installing zhparser PostgreSQL extension..."
    $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" cp "$ZHPARSER_SQL" postgres:/tmp/init_zhparser.sql
    $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" exec -T -e PGPASSWORD="${DB_PASSWORD}" postgres psql -U postgres -d "${DB_NAME}" -f /tmp/init_zhparser.sql
else
    log_warn "zhparser initialization SQL not found; migrations may fail on an empty database."
fi

# Restore database backup if provided
if [[ -n "$DB_BACKUP_FILE" ]]; then
    log_info "Restoring database backup: $DB_BACKUP_FILE"
    if [[ "$DB_BACKUP_FILE" == *.gz || "$DB_BACKUP_FILE" == *.gzip ]]; then
        gunzip -c "$DB_BACKUP_FILE" | $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" exec -T -e PGPASSWORD="${DB_PASSWORD}" postgres psql -U "${DB_USER}" -d "${DB_NAME}"
    else
        $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" exec -T -e PGPASSWORD="${DB_PASSWORD}" postgres psql -U "${DB_USER}" -d "${DB_NAME}" < "$DB_BACKUP_FILE"
    fi
    log_info "Database backup restored."
fi

log_info "Starting MCdesk stack..."
if [[ "$ENABLE_CLOUDFLARE" == "y" || "$ENABLE_CLOUDFLARE" == "yes" ]]; then
    $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" --profile cloudflare up -d
else
    $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" up -d
fi

# ---------------------------------------------------------------------------
# Wait for backend health
# ---------------------------------------------------------------------------
log_info "Waiting for mcdesk-backend to become healthy (this may take 1-2 minutes)..."
for i in {1..60}; do
    status=$(docker inspect --format='{{.State.Health.Status}}' mcdesk-backend 2>/dev/null || echo "starting")
    if [[ "$status" == "healthy" ]]; then
        echo ""
        log_info "Backend is healthy."
        break
    fi
    echo -n "."
    sleep 3
done

backend_status=$(docker inspect --format='{{.State.Health.Status}}' mcdesk-backend 2>/dev/null || echo "unknown")
if [[ "$backend_status" != "healthy" ]]; then
    echo ""
    log_warn "Backend did not become healthy within the expected time."

    # Preserve backend logs for post-install analysis without attempting any fixes.
    if docker inspect mcdesk-backend &>/dev/null; then
        ERROR_LOG_DIR="${INSTALL_DIR}/logs/errors"
        mkdir -p "$ERROR_LOG_DIR"
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        if $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" logs --no-color mcdesk-backend 2>&1 | grep -qi "flyway"; then
            ERROR_NAME="flyway-migration-error"
        else
            ERROR_NAME="backend-unhealthy"
        fi
        ERROR_LOG_FILE="${ERROR_LOG_DIR}/${TIMESTAMP}_${ERROR_NAME}.log"
        $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" logs --no-color mcdesk-backend > "$ERROR_LOG_FILE" 2>&1
        log_warn "Backend logs saved to: $ERROR_LOG_FILE"
    fi

    log_warn "Check logs with: $COMPOSE_CMD -f $INSTALL_DIR/docker-compose.yml logs -f mcdesk-backend"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================================="
echo "  MCdesk installation complete"
echo "============================================================================="
echo "  Local URL:       http://localhost:${FRONTEND_PORT}"
echo "  Install dir:     ${INSTALL_DIR}"
echo "  Database:        ${DB_NAME}"
echo "  DB user:         ${DB_USER}"
echo "  DB password:     ${DB_PASSWORD}"
echo ""
echo "  Useful commands:"
echo "    cd ${INSTALL_DIR}"
echo "    $COMPOSE_CMD --env-file .env ps"
echo "    $COMPOSE_CMD --env-file .env logs -f mcdesk-backend"
echo "    $COMPOSE_CMD --env-file .env logs -f mcdesk-frontend"
echo "============================================================================="

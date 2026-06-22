#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${OCG_CONFIG:-$HOME/.config/ocg}"
SERVER_CONFIG="${OCG_SERVER_CONFIG:-$CONFIG_DIR/server.yml}"
TERN_CONFIG="${TERN_CONF:-$CONFIG_DIR/tern.conf}"
OVERWRITE_CONFIG="${BOOTSTRAP_OVERWRITE_CONFIG:-false}"
INSTALL_DEPS="${BOOTSTRAP_INSTALL_DEPS:-true}"
INSTALL_POSTGRES_SERVER="${BOOTSTRAP_INSTALL_POSTGRES_SERVER:-false}"
RUN_BUILD="${BOOTSTRAP_BUILD:-true}"
RUN_MIGRATIONS="${BOOTSTRAP_MIGRATE:-true}"
RUN_SEED="${BOOTSTRAP_SEED:-true}"

DB_HOST="${OCG_DB_HOST:-127.0.0.1}"
DB_PORT="${OCG_DB_PORT:-5432}"
DB_NAME="${OCG_DB_NAME:-ocg}"
DB_USER="${OCG_DB_USER:-ocg}"
DB_PASSWORD="${OCG_DB_PASSWORD:-}"
BASE_URL="${OCG_BASE_URL:-https://goup.vc}"
SERVER_ADDR="${OCG_SERVER_ADDR:-127.0.0.1:9000}"

SITE_TITLE="${OCG_SITE_TITLE:-GOUP Alliance}"
SITE_DESCRIPTION="${OCG_SITE_DESCRIPTION:-GOUP Alliance}"
ALLIANCE_ID="${OCG_ALLIANCE_ID:-11111111-1111-1111-1111-111111111111}"
ALLIANCE_NAME="${OCG_ALLIANCE_NAME:-goup}"
ALLIANCE_DISPLAY_NAME="${OCG_ALLIANCE_DISPLAY_NAME:-GOUP Alliance}"
ALLIANCE_DESCRIPTION="${OCG_ALLIANCE_DESCRIPTION:-GOUP Alliance}"
GROUP_CATEGORY_ID="${OCG_GROUP_CATEGORY_ID:-22222222-2222-2222-2222-222222222222}"
GROUP_CATEGORY_NAME="${OCG_GROUP_CATEGORY_NAME:-General}"
GROUP_ID="${OCG_GROUP_ID:-33333333-3333-3333-3333-333333333333}"
GROUP_NAME="${OCG_GROUP_NAME:-GOUP}"
GROUP_SLUG="${OCG_GROUP_SLUG:-goup}"
GROUP_DESCRIPTION="${OCG_GROUP_DESCRIPTION:-GOUP members}"

LINKEDIN_CLIENT_ID="${OCG_LINKEDIN_CLIENT_ID:-}"
LINKEDIN_CLIENT_SECRET="${OCG_LINKEDIN_CLIENT_SECRET:-}"
SMTP_HOST="${OCG_SMTP_HOST:-}"
SMTP_PORT="${OCG_SMTP_PORT:-587}"
SMTP_USERNAME="${OCG_SMTP_USERNAME:-}"
SMTP_PASSWORD="${OCG_SMTP_PASSWORD:-}"
EMAIL_FROM_ADDRESS="${OCG_EMAIL_FROM_ADDRESS:-no-reply@goup.vc}"
EMAIL_FROM_NAME="${OCG_EMAIL_FROM_NAME:-GOUP Alliance}"
ADMIN_EMAIL="${OCG_ADMIN_EMAIL:-}"

usage() {
    cat <<'EOF'
Bootstrap a fresh GOUP EC2 deployment.

Required environment:
  OCG_DB_PASSWORD              Database password.
  OCG_LINKEDIN_CLIENT_ID       LinkedIn OIDC client ID.
  OCG_LINKEDIN_CLIENT_SECRET   LinkedIn OIDC client secret.

Common optional environment:
  OCG_BASE_URL                 Public URL. Default: https://goup.vc
  OCG_DB_HOST                  DB host. Default: 127.0.0.1
  OCG_DB_PORT                  DB port. Default: 5432
  OCG_DB_NAME                  DB name. Default: ocg
  OCG_DB_USER                  DB user. Default: ocg
  OCG_ADMIN_EMAIL              Existing user email to grant alliance admin.
  BOOTSTRAP_INSTALL_DEPS       Install missing EC2 dependencies. Default: true
  BOOTSTRAP_INSTALL_POSTGRES_SERVER
                               Also install local PostgreSQL/PostGIS packages when available.
                               Default: false
  BOOTSTRAP_OVERWRITE_CONFIG   Overwrite server.yml/tern.conf. Default: false
  BOOTSTRAP_BUILD              Build release binary. Default: true
  BOOTSTRAP_MIGRATE            Run migrations. Default: true
  BOOTSTRAP_SEED               Seed site/alliance/group. Default: true

Example:
  OCG_DB_PASSWORD='...' \
  OCG_LINKEDIN_CLIENT_ID='...' \
  OCG_LINKEDIN_CLIENT_SECRET='...' \
  OCG_ADMIN_EMAIL='you@example.com' \
  ./scripts/bootstrap-ec2.sh
EOF
}

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

sudo_cmd() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

install_first_available_package() {
    local package_manager="$1"
    shift

    for package_name in "$@"; do
        if sudo_cmd "$package_manager" install -y "$package_name"; then
            return
        fi
    done

    die "none of these packages could be installed: $*"
}

install_debian_deps() {
    local packages=(
        ca-certificates
        curl
        git
        build-essential
        pkg-config
        libssl-dev
        postgresql-client
        golang-go
    )

    if [[ "$INSTALL_POSTGRES_SERVER" == "true" ]]; then
        packages+=(postgresql postgresql-contrib postgis)
    fi

    sudo_cmd apt-get update
    sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

install_rhel_deps() {
    local package_manager="dnf"
    if ! command -v dnf >/dev/null 2>&1; then
        package_manager="yum"
    fi

    local packages=(
        ca-certificates
        curl
        git
        gcc
        gcc-c++
        make
        pkgconf-pkg-config
        openssl-devel
        golang
    )

    sudo_cmd "$package_manager" install -y "${packages[@]}"

    if ! command -v psql >/dev/null 2>&1; then
        install_first_available_package "$package_manager" postgresql16 postgresql15 postgresql14 postgresql
    fi

    if [[ "$INSTALL_POSTGRES_SERVER" == "true" ]]; then
        install_first_available_package "$package_manager" postgresql16-server postgresql15-server postgresql14-server postgresql-server

        if ! sudo_cmd "$package_manager" install -y postgis; then
            log "PostGIS package was not available from enabled repositories; install it manually for the PostgreSQL server you use."
        fi
    fi
}

install_system_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        install_debian_deps
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        install_rhel_deps
    else
        die "unsupported package manager; install curl git build tools openssl dev libs, psql, go, rust/cargo, and tern"
    fi
}

install_rust() {
    if command -v cargo >/dev/null 2>&1; then
        return
    fi

    log "Installing Rust toolchain"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
}

install_tern() {
    if command -v tern >/dev/null 2>&1; then
        return
    fi

    require_cmd go
    log "Installing tern"
    install -d "${GOBIN:-$HOME/go/bin}"
    GOBIN="${GOBIN:-$HOME/go/bin}" go install github.com/jackc/tern/v2@latest
    export PATH="$HOME/go/bin:$PATH"
}

install_dependencies() {
    if [[ "$INSTALL_DEPS" != "true" ]]; then
        return
    fi

    log "Installing EC2 dependencies"
    install_system_deps
    install_rust
    export PATH="$HOME/.cargo/bin:$HOME/go/bin:$PATH"
    install_tern
}

write_file_once() {
    local path="$1"
    local mode="$2"

    if [[ -e "$path" && "$OVERWRITE_CONFIG" != "true" ]]; then
        log "Keeping existing $path"
        return
    fi

    install -d "$(dirname "$path")"
    umask 077
    cat > "$path"
    chmod "$mode" "$path"
    log "Wrote $path"
}

sql_escape() {
    printf "%s" "$1" | sed "s/'/''/g"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

[[ -n "$DB_PASSWORD" ]] || die "set OCG_DB_PASSWORD"
[[ -n "$LINKEDIN_CLIENT_ID" ]] || die "set OCG_LINKEDIN_CLIENT_ID"
[[ -n "$LINKEDIN_CLIENT_SECRET" ]] || die "set OCG_LINKEDIN_CLIENT_SECRET"

install_dependencies

require_cmd cargo
require_cmd psql
require_cmd tern

log "Writing configuration"
write_file_once "$TERN_CONFIG" 600 <<EOF
[database]
host = $DB_HOST
port = $DB_PORT
database = $DB_NAME
user = $DB_USER
password = $DB_PASSWORD
EOF

write_file_once "$SERVER_CONFIG" 600 <<EOF
db:
  host: $DB_HOST
  port: $DB_PORT
  dbname: $DB_NAME
  user: $DB_USER
  password: $DB_PASSWORD
  pool:
    max_size: 25
    timeouts:
      recycle: { secs: 5, nanos: 0 }
      wait: { secs: 5, nanos: 0 }

email:
  from_address: "$EMAIL_FROM_ADDRESS"
  from_name: "$EMAIL_FROM_NAME"
  rcpts_whitelist: null
  smtp:
    host: "$SMTP_HOST"
    port: $SMTP_PORT
    username: "$SMTP_USERNAME"
    password: "$SMTP_PASSWORD"

images:
  provider: db

log:
  format: json

server:
  addr: $SERVER_ADDR
  base_url: $BASE_URL
  disable_referer_checks: false
  cookie:
    secure: true
  login:
    email: false
    github: false
    linkedin: true
  oauth2:
    github:
      auth_url: https://github.com/login/oauth/authorize
      client_id: ""
      client_secret: ""
      redirect_uri: "$BASE_URL/log-in/oauth2/github/callback"
      scopes: ["read:user", "user:email"]
      token_url: https://github.com/login/oauth/access_token
  oidc:
    linkedin:
      client_id: "$LINKEDIN_CLIENT_ID"
      client_secret: "$LINKEDIN_CLIENT_SECRET"
      issuer_url: https://www.linkedin.com
      redirect_uri: "$BASE_URL/log-in/oidc/linkedin/callback"
      scopes: ["openid", "profile", "email"]
EOF

if [[ "$RUN_BUILD" == "true" ]]; then
    log "Building release binary"
    (cd "$ROOT_DIR" && cargo build --release -p ocg-server)
fi

if [[ "$RUN_MIGRATIONS" == "true" ]]; then
    log "Running migrations"
    (cd "$ROOT_DIR/database/migrations" && TERN_CONF="$TERN_CONFIG" ./migrate.sh)
fi

if [[ "$RUN_SEED" == "true" ]]; then
    log "Seeding initial GOUP records"
    PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -v ON_ERROR_STOP=1 <<SQL
insert into site (site_id, title, description, theme)
values (
  '00000000-0000-0000-0000-000000000000',
  '$(sql_escape "$SITE_TITLE")',
  '$(sql_escape "$SITE_DESCRIPTION")',
  '{"primary_color":"#0EA5E9"}'
)
on conflict do nothing;

insert into alliance (
  alliance_id,
  name,
  display_name,
  description,
  banner_url,
  banner_mobile_url,
  logo_url
) values (
  '$ALLIANCE_ID',
  '$(sql_escape "$ALLIANCE_NAME")',
  '$(sql_escape "$ALLIANCE_DISPLAY_NAME")',
  '$(sql_escape "$ALLIANCE_DESCRIPTION")',
  '/static/images/e2e/alliance-primary-banner.svg',
  '/static/images/e2e/alliance-primary-banner-mobile.svg',
  '/static/images/e2e/alliance-primary-logo.svg'
)
on conflict do nothing;

insert into group_category (group_category_id, alliance_id, name)
values (
  '$GROUP_CATEGORY_ID',
  '$ALLIANCE_ID',
  '$(sql_escape "$GROUP_CATEGORY_NAME")'
)
on conflict do nothing;

insert into "group" (
  group_id,
  alliance_id,
  group_category_id,
  name,
  slug,
  description
) values (
  '$GROUP_ID',
  '$ALLIANCE_ID',
  '$GROUP_CATEGORY_ID',
  '$(sql_escape "$GROUP_NAME")',
  '$(sql_escape "$GROUP_SLUG")',
  '$(sql_escape "$GROUP_DESCRIPTION")'
)
on conflict do nothing;
SQL
fi

if [[ -n "$ADMIN_EMAIL" ]]; then
    log "Granting alliance admin to $ADMIN_EMAIL if the user exists"
    PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -v ON_ERROR_STOP=1 <<SQL
insert into alliance_team (alliance_id, user_id, accepted, role)
select '$ALLIANCE_ID', user_id, true, 'admin'
from "user"
where lower(email) = lower('$(sql_escape "$ADMIN_EMAIL")')
on conflict (alliance_id, user_id)
do update set accepted = true, role = 'admin';
SQL
else
    log "Skipping admin grant; set OCG_ADMIN_EMAIL after first LinkedIn login to grant admin"
fi

cat <<EOF

Bootstrap complete.

Start the server:
  $ROOT_DIR/target/release/ocg-server -c "$SERVER_CONFIG"

LinkedIn redirect URL to configure:
  $BASE_URL/log-in/oidc/linkedin/callback

If you skipped admin grant, log in once with LinkedIn, then rerun:
  OCG_ADMIN_EMAIL='you@example.com' BOOTSTRAP_BUILD=false BOOTSTRAP_MIGRATE=false BOOTSTRAP_SEED=false $0
EOF

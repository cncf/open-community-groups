#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MCP_DIR="${MCP_DIR:-$ROOT_DIR/mcp}"
CONFIG_DIR="${OCG_CONFIG:-$HOME/.config/ocg}"
ENV_FILE="${MCP_ENV_FILE:-$CONFIG_DIR/mcp.env}"
TERN_CONFIG="${TERN_CONF:-$CONFIG_DIR/tern.conf}"

SERVICE_NAME="${MCP_SERVICE_NAME:-goup-mcp}"
MCP_HOST="${MCP_HOST:-127.0.0.1}"
MCP_PORT="${MCP_PORT:-8787}"
MCP_ENABLE_MUTATIONS="${MCP_ENABLE_MUTATIONS:-false}"
MCP_PUBLIC_URL="${MCP_PUBLIC_URL:-https://goup.vc/mcp}"
INSTALL_DEPS="${SETUP_MCP_INSTALL_DEPS:-true}"
INSTALL_SYSTEMD_SERVICE="${SETUP_MCP_SYSTEMD_SERVICE:-true}"
START_SERVICE="${SETUP_MCP_START_SERVICE:-true}"

usage() {
    cat <<'EOF'
Set up the GOUP remote MCP server on EC2.

Common environment:
  MCP_BEARER_TOKEN            Token used by MCP clients. Generated if omitted.
  MCP_ENABLE_MUTATIONS        Enable tools that create/change data. Default: false
  MCP_HOST                    Local bind host. Default: 127.0.0.1
  MCP_PORT                    Local bind port. Default: 8787
  MCP_PUBLIC_URL              Public URL shown in client config. Default: https://goup.vc/mcp
  TERN_CONF                   DB config used by mutation/search tools. Default: ~/.config/ocg/tern.conf
  DATABASE_URL                Optional DB URL; if set, MCP tools use it instead of TERN_CONF.
  SETUP_MCP_INSTALL_DEPS      Install node/npm if missing. Default: true
  SETUP_MCP_SYSTEMD_SERVICE   Install systemd service. Default: true
  SETUP_MCP_START_SERVICE     Start/restart service. Default: true

Examples:
  ./scripts/setup-mcp-ec2.sh

  MCP_ENABLE_MUTATIONS=true \
  MCP_PUBLIC_URL='https://goup.vc/mcp' \
  ./scripts/setup-mcp-ec2.sh
EOF
}

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

sudo_cmd() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

install_deps() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        return
    fi

    [[ "$INSTALL_DEPS" == "true" ]] || die "node/npm not found; install Node.js 20+ or set SETUP_MCP_INSTALL_DEPS=true"

    log "Installing Node.js and npm"
    if command -v apt-get >/dev/null 2>&1; then
        sudo_cmd apt-get update
        sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs npm
    elif command -v dnf >/dev/null 2>&1; then
        sudo_cmd dnf install -y nodejs npm
    elif command -v yum >/dev/null 2>&1; then
        sudo_cmd yum install -y nodejs npm
    else
        die "unsupported package manager; install Node.js 20+ and npm manually"
    fi
}

check_node_version() {
    require_cmd node
    require_cmd npm

    local major
    major="$(node -p 'Number(process.versions.node.split(".")[0])')"
    if [[ "$major" -lt 20 ]]; then
        die "Node.js 20+ is required; found $(node --version)"
    fi
}

load_existing_token() {
    if [[ -n "${MCP_BEARER_TOKEN:-}" ]]; then
        printf '%s' "$MCP_BEARER_TOKEN"
        return
    fi

    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        if [[ -n "${MCP_BEARER_TOKEN:-}" ]]; then
            printf '%s' "$MCP_BEARER_TOKEN"
            return
        fi
    fi

    openssl rand -base64 32
}

write_env_file() {
    local token="$1"

    log "Writing MCP environment file"
    mkdir -p "$CONFIG_DIR"
    umask 077
    cat > "$ENV_FILE" <<EOF
MCP_HOST=$MCP_HOST
MCP_PORT=$MCP_PORT
MCP_BEARER_TOKEN=$token
MCP_ENABLE_MUTATIONS=$MCP_ENABLE_MUTATIONS
TERN_CONF=$TERN_CONFIG
EOF

    if [[ -n "${DATABASE_URL:-}" ]]; then
        printf 'DATABASE_URL=%s\n' "$DATABASE_URL" >> "$ENV_FILE"
    fi

    chmod 600 "$ENV_FILE"
}

install_systemd_service() {
    [[ "$INSTALL_SYSTEMD_SERVICE" == "true" ]] || return

    log "Installing systemd service $SERVICE_NAME"
    sudo_cmd tee "/etc/systemd/system/$SERVICE_NAME.service" >/dev/null <<EOF
[Unit]
Description=GOUP remote MCP server
After=network.target

[Service]
Type=simple
WorkingDirectory=$MCP_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$(command -v npm) start
Restart=always
RestartSec=5
User=$(id -un)

[Install]
WantedBy=multi-user.target
EOF

    sudo_cmd systemctl daemon-reload
    sudo_cmd systemctl enable "$SERVICE_NAME"

    if [[ "$START_SERVICE" == "true" ]]; then
        sudo_cmd systemctl restart "$SERVICE_NAME"
    fi
}

print_next_steps() {
    local token="$1"

    cat <<EOF

MCP setup complete.

Bearer token:
$token

Local checks:
  curl -H "Authorization: Bearer $token" http://$MCP_HOST:$MCP_PORT/health
  curl -H "Authorization: Bearer $token" \\
    -H "content-type: application/json" \\
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \\
    http://$MCP_HOST:$MCP_PORT/mcp

NGINX location snippet:
  location /mcp {
      proxy_pass http://$MCP_HOST:$MCP_PORT/mcp;
      proxy_http_version 1.1;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
  }

Cursor/client config:
{
  "mcpServers": {
    "goup-vc": {
      "url": "$MCP_PUBLIC_URL",
      "headers": {
        "Authorization": "Bearer $token"
      }
    }
  }
}

Service status:
  sudo systemctl status $SERVICE_NAME --no-pager
  sudo journalctl -u $SERVICE_NAME -n 100 --no-pager
EOF
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    [[ -d "$MCP_DIR" ]] || die "MCP directory not found: $MCP_DIR"
    require_cmd openssl
    install_deps
    check_node_version

    local token
    token="$(load_existing_token)"
    write_env_file "$token"
    install_systemd_service
    print_next_steps "$token"
}

main "$@"

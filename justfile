# Open Community Groups - Development Tasks
#
# Configuration: Set these environment variables
#
#   Optional (with defaults):
#     OCG_CONFIG        - Path to config directory (default: $HOME/.config/ocg)
#     OCG_DB_HOST       - Database host or unix socket path (default: localhost)
#     OCG_DB_NAME       - Main database name (default: ocg)
#     OCG_DB_NAME_TESTS - Test database name (default: ocg_tests)
#     OCG_DB_PORT       - Database port (default: 5432)
#     OCG_DB_USER       - Database user (default: postgres)
#     OCG_PG_BIN        - Path to PostgreSQL binaries (default: /opt/homebrew/opt/postgresql@17/bin)
#
# Please don't forget to set up the tern config files (tern.conf and tern-tests.conf) in
# the config directory (OCG_CONFIG). Make sure the database connection settings match the
# environment variables set here.
# Configuration

config_dir := env("OCG_CONFIG", env_var("HOME") / ".config/ocg")
db_host := env("OCG_DB_HOST", "localhost")
db_name := env("OCG_DB_NAME", "ocg")
db_name_tests := env("OCG_DB_NAME_TESTS", "ocg_tests")
db_name_tests_e2e := env("OCG_DB_NAME_E2E", "ocg_tests_e2e")
db_port := env("OCG_DB_PORT", "5432")
db_user := env("OCG_DB_USER", "postgres")
db_password := env("OCG_DB_PASSWORD", "")
pg_bin := env("OCG_PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
pg_conn := "-h " + db_host + " -p " + db_port + " -U " + db_user
db_server_host_opt := if db_host =~ '^/' { "-k " + db_host } else { "-h " + db_host }
source_dir := justfile_directory()
e2e_tern_conf := env("OCG_E2E_TERN_CONF", "/tmp/ocg-tern-e2e.conf")
e2e_server_config := env("OCG_E2E_SERVER_CONFIG", "/tmp/ocg-e2e.yml")
e2e_base_url := env("OCG_E2E_BASE_URL", "http://localhost:9000")
e2e_server_addr := env("OCG_E2E_SERVER_ADDR", "127.0.0.1:9000")
e2e_server_base_url := env("OCG_E2E_SERVER_BASE_URL", e2e_base_url)

# Helper to run PostgreSQL commands with the configured binary path
[private]
pg command *args:
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" {{ command }} {{ args }}

# Database

# Connect to main database.
db-client:
    just pg psql {{ pg_conn }} {{ db_name }}

# Connect to test database.
db-client-tests:
    just pg psql {{ pg_conn }} {{ db_name_tests }}

# Create main database.
db-create:
    just pg createdb {{ pg_conn }} {{ db_name }}

# Create test database with pgtap extension.
db-create-tests:
    just pg createdb {{ pg_conn }} {{ db_name_tests }}
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests }} -c "CREATE EXTENSION IF NOT EXISTS pgtap"

# Drop main database.
db-drop:
    just pg dropdb {{ pg_conn }} --if-exists --force {{ db_name }}

# Drop test database.
db-drop-tests:
    just pg dropdb {{ pg_conn }} --if-exists --force {{ db_name_tests }}

# Initialize PostgreSQL data directory.
db-init data_dir:
    mkdir -p "{{ data_dir }}"
    just pg initdb -U {{ db_user }} "{{ data_dir }}"

# Run migrations on main database.
db-migrate:
    cd "{{ source_dir }}/database/migrations" && TERN_CONF="{{ config_dir }}/tern.conf" ./migrate.sh

# Run migrations on test database.
db-migrate-tests:
    cd "{{ source_dir }}/database/migrations" && TERN_CONF="{{ config_dir }}/tern-tests.conf" ./migrate.sh

# Drop, create, and migrate main database.
db-recreate: db-drop db-create db-migrate

# Drop, create, and migrate test database.
db-recreate-tests: db-drop-tests db-create-tests db-migrate-tests

# Start PostgreSQL server.
db-server data_dir:
    just pg postgres -D "{{ data_dir }}" -p {{ db_port }} {{ db_server_host_opt }}

# Run database tests (recreates test db and runs pgTAP tests).
db-tests: db-recreate-tests
    pg_prove -h {{ db_host }} -p {{ db_port }} -d {{ db_name_tests }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -v $(find "{{ source_dir }}/database/tests/schema" "{{ source_dir }}/database/tests/functions" -type f -name '*.sql' | sort)

# Run database tests on a specific file.
db-tests-file file: db-migrate-tests
    pg_prove -h {{ db_host }} -p {{ db_port }} -d {{ db_name_tests }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -v {{ file }}

# Redirector

# Run the redirector using cargo run (builds if needed).
redirector:
    cargo run -p ocg-redirector -- -c "{{ config_dir }}/redirector.yml"

# Build the redirector binary.
redirector-build:
    cargo build -p ocg-redirector

# Format and lint redirector code.
redirector-fmt-and-lint:
    cargo fmt
    cargo check -p ocg-redirector
    cargo clippy -p ocg-redirector --all-targets --all-features -- --deny warnings

# Run redirector tests.
redirector-tests:
    cargo test -p ocg-redirector

# Server

# Run the server using cargo run (builds if needed).
server:
    cargo run -p ocg-server -- -c "{{ config_dir }}/server.yml"

# Build the server binary.
server-build:
    cargo build -p ocg-server

# Format and lint server code.
server-fmt-and-lint:
    cargo fmt
    cargo check -p ocg-server
    cargo clippy -p ocg-server --all-targets --all-features -- --deny warnings

# Run server tests.
server-tests:
    cargo test -p ocg-server

# Run the server with cargo watch for auto-reload.
server-watch:
    cargo watch -x "run -p ocg-server -- -c {{ config_dir }}/server.yml"

# Frontend

# Format and lint frontend code.
frontend-fmt-and-lint:
    prettier --config ocg-server/static/js/.prettierrc.yaml --write "ocg-server/static/js/**/*.js"
    djlint --check --configuration ocg-server/templates/.djlintrc ocg-server/templates

# E2E

[private]
e2e-write-tern-config:
    printf '%s\n' \
    "[database]" \
    "host = {{ db_host }}" \
    "port = {{ db_port }}" \
    "database = {{ db_name_tests_e2e }}" \
    "user = {{ db_user }}" \
    "password = {{ db_password }}" \
    > "{{ e2e_tern_conf }}"

[private]
e2e-write-server-config:
    #!/usr/bin/env bash
    set -euo pipefail
    server_addr="{{ e2e_server_addr }}"
    server_base_url="{{ e2e_server_base_url }}"
    if [ -z "${OCG_E2E_SERVER_ADDR:-}" ] && [[ "$server_base_url" =~ ^http://(localhost|127\.0\.0\.1):([0-9]+)$ ]]; then
        server_addr="127.0.0.1:${BASH_REMATCH[2]}"
    fi
    {
        printf '%s\n' \
        "db:" \
        "  host: {{ db_host }}" \
        "  port: {{ db_port }}" \
        "  dbname: {{ db_name_tests_e2e }}" \
        "  user: {{ db_user }}" \
        "  password: \"{{ db_password }}\"" \
        "email:" \
        "  from_address: noreply@test.com" \
        "  from_name: Test" \
        "  smtp:" \
        "    host: localhost" \
        "    port: 1025" \
        "    username: \"\"" \
        "    password: \"\"" \
        "images:" \
        "  provider: db" \
        "server:" \
        "  addr: ${server_addr}" \
        "  base_url: ${server_base_url}" \
        "  cookie:" \
        "    secure: false" \
        "  disable_referer_checks: false" \
        "  login:" \
        "    email: true" \
        "    github: false" \
        "    linuxfoundation: false" \
        "  oauth2: {}" \
        "  oidc: {}"
    } > "{{ e2e_server_config }}"

# Run the server with a recreated e2e database and generated config.
e2e-server: e2e-db-setup e2e-write-server-config
    cargo run -p ocg-server -- -c "{{ e2e_server_config }}"

# Install e2e dependencies and Playwright browsers.
e2e-install:
    npm install --no-package-lock
    npx playwright install --with-deps

# Recreate and migrate the e2e test database.
[private]
e2e-db-recreate: e2e-write-tern-config
    just pg dropdb {{ pg_conn }} --if-exists --force {{ db_name_tests_e2e }}
    just pg createdb {{ pg_conn }} {{ db_name_tests_e2e }}
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests_e2e }} -c "CREATE EXTENSION IF NOT EXISTS pgcrypto"
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests_e2e }} -c "CREATE EXTENSION IF NOT EXISTS postgis"
    cd "{{ source_dir }}/database/migrations" && TERN_CONF="{{ e2e_tern_conf }}" ./migrate.sh

# Load seeded data into the e2e test database.
[private]
e2e-db-load-data:
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests_e2e }} -f "{{ source_dir }}/database/tests/data/e2e.sql"
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests_e2e }} -c "update \"user\" set password = '\$argon2id\$v=19\$m=19456,t=2,p=1\$q55jlxUx8bffhFM3xN36ZA\$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g' where username like 'e2e-%'"

# Set up the e2e test database.
e2e-db-setup: e2e-db-recreate e2e-db-load-data

# Run the Playwright e2e test suite.
e2e-tests:
    npx playwright test --config tests/e2e/playwright.config.ts

# Update Playwright visual snapshots for the e2e suite.
e2e-update-snapshots:
    npx playwright test --config tests/e2e/playwright.config.ts tests/e2e/visual/visual.spec.ts --project=chromium-deep --project=chromium-mobile-deep --update-snapshots

# Run full e2e setup: dependencies, database, server, and tests.
e2e-full: e2e-install
    OCG_E2E_START_SERVER=true OCG_E2E_SERVER_CMD='just e2e-server' npx playwright test --config tests/e2e/playwright.config.ts

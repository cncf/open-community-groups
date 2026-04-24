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
db_port := env("OCG_DB_PORT", "5432")
db_user := env("OCG_DB_USER", "postgres")
db_password := env("OCG_DB_PASSWORD", "")
pg_bin := env("OCG_PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
pg_conn := "-h " + db_host + " -p " + db_port + " -U " + db_user
db_server_host_opt := if db_host =~ '^/' { "-k " + db_host } else { "-h " + db_host }
source_dir := justfile_directory()

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

# Load e2e seed data into main database.
db-load-e2e-data:
    just pg psql {{ pg_conn }} {{ db_name }} -f "{{ source_dir }}/database/tests/data/e2e.sql"
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name }} -c 'update "user" set password = $$$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g$$ where username like $$e2e-%$$'

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

# Run the server with watchexec for auto-reload.
server-watch:
    watchexec -r -- cargo run -p ocg-server -- -c "{{ config_dir }}/server.yml"

# Frontend

# Format and lint frontend code.
frontend-fmt-and-lint:
    prettier --config ocg-server/static/js/.prettierrc.yaml --write "ocg-server/static/js/**/*.js"
    djlint --check --configuration ocg-server/templates/.djlintrc ocg-server/templates

# Run frontend unit tests.
frontend-unit-tests:
    npm --prefix tests/unit test

# E2E

# Install e2e dependencies and Playwright browsers.
e2e-install:
    cd tests/e2e && npm ci
    cd tests/e2e && npx playwright install --with-deps

# Run the Playwright e2e test suite.
e2e-tests:
    cd tests/e2e && OCG_E2E_MEETINGS_ENABLED=true OCG_E2E_PAYMENTS_ENABLED=true npx playwright test --config playwright.config.ts

# Update Playwright visual snapshots for the e2e suite.
e2e-update-snapshots:
    cd tests/e2e && npx playwright test --config playwright.config.ts --grep @visual --project=chromium-deep --project=chromium-mobile-deep --update-snapshots

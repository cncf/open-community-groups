# Open Community Groups - Development Tasks
#
# Configuration: Set these environment variables
#
#   Optional (with defaults):
#     OCG_CONFIG                  - Path to config directory (default: $HOME/.config/ocg)
#     OCG_DB_HOST                 - Database host or unix socket path (default: localhost)
#     OCG_DB_NAME                 - Main database name (default: ocg)
#     OCG_DB_NAME_TESTS           - Test database name (default: ocg_tests)
#     OCG_DB_NAME_TESTS_CONTRACT  - Contract test database name (default: ocg_tests_contract)
#     OCG_DB_NAME_TESTS_E2E       - E2E test database name (default: ocg_tests_e2e)
#     OCG_DB_PORT                 - Database port (default: 5432)
#     OCG_DB_USER                 - Database user (default: postgres)
#     OCG_PG_BIN                  - Path to PostgreSQL binaries (default: /opt/homebrew/opt/postgresql@17/bin)
#     OCG_SERVER_CONFIG           - Server config path (default: $OCG_CONFIG/server.yml)
#     OCG_SERVER_CONFIG_TESTS_E2E - E2E server config path (default: $OCG_CONFIG/server-tests-e2e.yml)
#
# Please don't forget to set up the tern config files (tern.conf, tern-e2e-tests.conf,
# tern-tests.conf, and tern-tests-contract.conf) in the config directory (OCG_CONFIG). Make sure the database
# connection settings match the environment variables set here.
# Configuration

config_dir := env("OCG_CONFIG", env_var("HOME") / ".config/ocg")
db_host := env("OCG_DB_HOST", "localhost")
db_name := env("OCG_DB_NAME", "ocg")
db_name_tests := env("OCG_DB_NAME_TESTS", "ocg_tests")
db_name_tests_contract := env("OCG_DB_NAME_TESTS_CONTRACT", "ocg_tests_contract")
db_name_tests_e2e := env("OCG_DB_NAME_TESTS_E2E", "ocg_tests_e2e")
db_port := env("OCG_DB_PORT", "5432")
db_user := env("OCG_DB_USER", "postgres")
db_password := env("OCG_DB_PASSWORD", "")
pg_bin := env("OCG_PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
pg_conn := "-h " + db_host + " -p " + db_port + " -U " + db_user
db_server_host_opt := if db_host =~ '^/' { "-k " + db_host } else { "-h " + db_host }
server_config := env("OCG_SERVER_CONFIG", config_dir / "server.yml")
server_config_tests_e2e := env("OCG_SERVER_CONFIG_TESTS_E2E", config_dir / "server-tests-e2e.yml")
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

# Connect to contract test database.
db-client-tests-contract:
    just pg psql {{ pg_conn }} {{ db_name_tests_contract }}

# Connect to e2e test database.
db-client-tests-e2e:
    just pg psql {{ pg_conn }} {{ db_name_tests_e2e }}

# Run Rust database contract tests against the contract test database.
db-contract-tests: db-recreate-tests-contract
    OCG_DB_NAME_TESTS_CONTRACT="{{ db_name_tests_contract }}" cargo test -p ocg-server db_contracts -- --ignored --test-threads=1

# Create main database.
db-create:
    just pg createdb {{ pg_conn }} {{ db_name }}

# Create test database with pgtap extension.
db-create-tests:
    just pg createdb {{ pg_conn }} {{ db_name_tests }}
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests }} -c "CREATE EXTENSION IF NOT EXISTS pgtap"

# Create contract test database.
db-create-tests-contract:
    just pg createdb {{ pg_conn }} {{ db_name_tests_contract }}

# Create e2e test database.
db-create-tests-e2e:
    just pg createdb {{ pg_conn }} {{ db_name_tests_e2e }}

# Drop main database.
db-drop:
    just pg dropdb {{ pg_conn }} --if-exists --force {{ db_name }}

# Drop test database.
db-drop-tests:
    just pg dropdb {{ pg_conn }} --if-exists --force {{ db_name_tests }}

# Drop contract test database.
db-drop-tests-contract:
    just pg dropdb {{ pg_conn }} --if-exists --force {{ db_name_tests_contract }}

# Drop e2e test database.
db-drop-tests-e2e:
    just pg dropdb {{ pg_conn }} --if-exists --force {{ db_name_tests_e2e }}

# Initialize PostgreSQL data directory.
db-init data_dir:
    mkdir -p "{{ data_dir }}"
    just pg initdb -U {{ db_user }} "{{ data_dir }}"

# Load e2e seed data into e2e test database.
db-load-tests-e2e-data:
    just pg psql {{ pg_conn }} {{ db_name_tests_e2e }} -f "{{ source_dir }}/database/tests/data/e2e.sql"
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests_e2e }} -c 'update "user" set password = $$$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g$$ where username like $$e2e-%$$'

# Load contract test seed data into contract test database.
db-load-tests-contract-data:
    just pg psql {{ pg_conn }} {{ db_name_tests_contract }} -f "{{ source_dir }}/database/tests/data/contract.sql"

# Run migrations on main database.
db-migrate:
    @output=$(cd "{{ source_dir }}/database/migrations" && TERN_CONF="{{ config_dir }}/tern.conf" ./migrate.sh 2>&1); status=$?; if [ $status -ne 0 ]; then printf '%s\n' "$output"; fi; exit $status

# Run migrations on test database.
db-migrate-tests:
    @output=$(cd "{{ source_dir }}/database/migrations" && TERN_CONF="{{ config_dir }}/tern-tests.conf" ./migrate.sh 2>&1); status=$?; if [ $status -ne 0 ]; then printf '%s\n' "$output"; fi; exit $status

# Run migrations on contract test database.
db-migrate-tests-contract:
    @output=$(cd "{{ source_dir }}/database/migrations" && TERN_CONF="{{ config_dir }}/tern-tests-contract.conf" ./migrate.sh 2>&1); status=$?; if [ $status -ne 0 ]; then printf '%s\n' "$output"; fi; exit $status

# Run migrations on e2e test database.
db-migrate-tests-e2e:
    @output=$(cd "{{ source_dir }}/database/migrations" && TERN_CONF="{{ config_dir }}/tern-e2e-tests.conf" ./migrate.sh 2>&1); status=$?; if [ $status -ne 0 ]; then printf '%s\n' "$output"; fi; exit $status

# Drop, create, and migrate main database.
db-recreate: db-drop db-create db-migrate

# Drop, create, and migrate test database.
db-recreate-tests: db-drop-tests db-create-tests db-migrate-tests

# Drop, create, migrate, and seed contract test database.
db-recreate-tests-contract: db-drop-tests-contract db-create-tests-contract db-migrate-tests-contract db-load-tests-contract-data

# Drop, create, and migrate e2e test database.
db-recreate-tests-e2e: db-drop-tests-e2e db-create-tests-e2e db-migrate-tests-e2e

# Start PostgreSQL server.
db-server data_dir:
    just pg postgres -D "{{ data_dir }}" -p {{ db_port }} {{ db_server_host_opt }}

# Run database tests (recreates test db and runs pgTAP tests).
db-tests: db-recreate-tests
    @pg_prove -h {{ db_host }} -p {{ db_port }} -d {{ db_name_tests }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -Q -f $(find "{{ source_dir }}/database/tests/schema" "{{ source_dir }}/database/tests/functions" -type f -name '*.sql' | sort)

# Run database tests on a specific file.
db-tests-file file: db-migrate-tests
    @pg_prove -h {{ db_host }} -p {{ db_port }} -d {{ db_name_tests }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -Q -f {{ file }}

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
    cargo run -p ocg-server -- -c "{{ server_config }}"

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
    @output=$(cargo test -p ocg-server -- --quiet 2>&1); status=$?; if [ $status -eq 0 ]; then printf '%s\n' "$output" | awk '/^test result:/'; elif printf '%s\n' "$output" | grep -q '^test result:'; then printf '%s\n' "$output" | awk 'show || /^failures:/ { show = 1; print }'; else printf '%s\n' "$output"; fi; exit $status

# Run the server with watchexec for auto-reload.
server-watch:
    watchexec -r -- cargo run -p ocg-server -- -c "{{ server_config }}"

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

# Run the e2e server using cargo run (builds if needed).
e2e-server:
    cargo run -p ocg-server -- -c "{{ server_config_tests_e2e }}"

# Run the e2e server with watchexec for auto-reload.
e2e-server-watch:
    watchexec -r -- cargo run -p ocg-server -- -c "{{ server_config_tests_e2e }}"

# Run the Playwright e2e test suite.
e2e-tests:
    cd tests/e2e && OCG_E2E_MEETINGS_ENABLED=true OCG_E2E_PAYMENTS_ENABLED=true npx playwright test --config playwright.config.ts

# Update Playwright visual snapshots for the e2e suite.
e2e-update-snapshots:
    cd tests/e2e && npx playwright test --config playwright.config.ts --grep @visual --project=chromium-deep --project=chromium-mobile-deep --update-snapshots

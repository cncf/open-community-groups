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
#     OCG_DB_NAME_TESTS_MIGRATION - Migration test database name (default: ocg_tests_migration)
#     OCG_DB_PORT                 - Database port (default: 5432)
#     OCG_DB_USER                 - Database user (default: postgres)
#     OCG_PG_BIN                  - Path to PostgreSQL binaries (default: /opt/homebrew/opt/postgresql@17/bin)
#     OCG_SERVER_CONFIG           - Server config path (default: $OCG_CONFIG/server.yml)
#
#   E2E contract (exported to tern, psql, the e2e server and Playwright):
#     OCG_E2E_DB_HOST             - E2E database host (default: OCG_DB_HOST)
#     OCG_E2E_DB_NAME             - E2E database name, must end in `_e2e` (default: ocg_tests_e2e)
#     OCG_E2E_DB_PASSWORD         - E2E database password (default: OCG_DB_PASSWORD)
#     OCG_E2E_DB_PORT             - E2E database port (default: OCG_DB_PORT)
#     OCG_E2E_DB_USER             - E2E database user (default: OCG_DB_USER)
#     OCG_E2E_BASE_URL            - E2E server base URL (default: http://127.0.0.1:9001)
#
# Please don't forget to set up the tern config files (tern.conf, tern-tests.conf, and
# tern-tests-contract.conf) in the config directory (OCG_CONFIG). Make sure the database
# connection settings match the environment variables set here. The e2e suite uses the
# committed tests/e2e/config/{server.yml,tern.conf} instead.
# Configuration

config_dir := env("OCG_CONFIG", env_var("HOME") / ".config/ocg")
db_host := env("OCG_DB_HOST", "localhost")
db_name := env("OCG_DB_NAME", "ocg")
db_name_tests := env("OCG_DB_NAME_TESTS", "ocg_tests")
db_name_tests_contract := env("OCG_DB_NAME_TESTS_CONTRACT", "ocg_tests_contract")
db_name_tests_migration := env("OCG_DB_NAME_TESTS_MIGRATION", "ocg_tests_migration")
db_port := env("OCG_DB_PORT", "5432")
db_user := env("OCG_DB_USER", "postgres")
db_password := env("OCG_DB_PASSWORD", "")
pg_bin := env("OCG_PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
pg_conn := "-h " + db_host + " -p " + db_port + " -U " + db_user
db_server_host_opt := if db_host =~ '^/' { "-k " + db_host } else { "-h " + db_host }
server_config := env("OCG_SERVER_CONFIG", config_dir / "server.yml")
source_dir := justfile_directory()

# E2E contract: exported so tern (templated config), psql and Playwright share one target.

export OCG_E2E_BASE_URL := env("OCG_E2E_BASE_URL", "http://127.0.0.1:9001")
export OCG_E2E_DB_HOST := env("OCG_E2E_DB_HOST", db_host)
export OCG_E2E_DB_NAME := env("OCG_E2E_DB_NAME", "ocg_tests_e2e")
export OCG_E2E_DB_PASSWORD := env("OCG_E2E_DB_PASSWORD", db_password)
export OCG_E2E_DB_PORT := env("OCG_E2E_DB_PORT", db_port)
export OCG_E2E_DB_USER := env("OCG_E2E_DB_USER", db_user)

# Fake provider webhook secrets; keep in sync with tests/e2e/config/server.yml.

export OCG_E2E_STRIPE_CONNECTED_WEBHOOK_SECRET := "whsec_connect_e2e"
export OCG_E2E_STRIPE_WEBHOOK_SECRET := "whsec_e2e"
export OCG_E2E_ZOOM_WEBHOOK_SECRET := "whsec_zoom_e2e"
e2e_pg_conn := "-h " + OCG_E2E_DB_HOST + " -p " + OCG_E2E_DB_PORT + " -U " + OCG_E2E_DB_USER
e2e_seed_file := source_dir / "database/tests/data/e2e.sql"
e2e_server_config := source_dir / "tests/e2e/config/server.yml"
e2e_tern_config := source_dir / "tests/e2e/config/tern.conf"

# Helper to run PostgreSQL commands with the configured binary path
[private]
pg command *args:
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" {{ command }} {{ args }}

# Helper to run PostgreSQL commands against the e2e database contract.
[private]
e2e-pg command *args:
    PGPASSWORD="{{ OCG_E2E_DB_PASSWORD }}" PATH="{{ pg_bin }}:$PATH" {{ command }} {{ args }}

# Helper that refuses destructive e2e operations on databases not named `*_e2e`.
[private]
e2e-db-guard:
    @case "{{ OCG_E2E_DB_NAME }}" in *_e2e) ;; *) echo "error: OCG_E2E_DB_NAME must end in _e2e (got '{{ OCG_E2E_DB_NAME }}')" >&2; exit 1 ;; esac

# Common

# Format and lint shared crate code.
common-fmt-and-lint:
    cargo fmt
    cargo check -p ocg-common
    cargo clippy -p ocg-common --all-targets --all-features -- --deny warnings

# Run shared crate tests.
common-tests:
    cargo test -p ocg-common

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
    just e2e-pg psql {{ e2e_pg_conn }} {{ OCG_E2E_DB_NAME }}

# Connect to migration test database.
db-client-tests-migration:
    just pg psql {{ pg_conn }} {{ db_name_tests_migration }}

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
db-create-tests-e2e: e2e-db-guard
    just e2e-pg createdb {{ e2e_pg_conn }} {{ OCG_E2E_DB_NAME }}

# Create migration test database with pgTAP extension.
db-create-tests-migration:
    just pg createdb {{ pg_conn }} {{ db_name_tests_migration }}
    PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests_migration }} -c "CREATE EXTENSION IF NOT EXISTS pgtap"

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
db-drop-tests-e2e: e2e-db-guard
    just e2e-pg dropdb {{ e2e_pg_conn }} --if-exists --force {{ OCG_E2E_DB_NAME }}

# Drop migration test database.
db-drop-tests-migration:
    just pg dropdb {{ pg_conn }} --if-exists --force {{ db_name_tests_migration }}

# Initialize PostgreSQL data directory.
db-init data_dir:
    mkdir -p "{{ data_dir }}"
    just pg initdb -U {{ db_user }} "{{ data_dir }}"

# Install pgTAP fixture functions (fx_*) into the test database.
db-install-tests-fixtures:
    @for file in "{{ source_dir }}"/database/tests/fixtures/*.sql; do PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests }} -q -v ON_ERROR_STOP=1 -f "$file" || exit 1; done

# Check database layer conventions (trigger function ownership).
db-lint:
    sh "{{ source_dir }}/database/scripts/lint.sh"

# Load e2e seed data into e2e test database.
db-load-tests-e2e-data: e2e-db-guard
    just e2e-pg psql {{ e2e_pg_conn }} {{ OCG_E2E_DB_NAME }} -X -q -v ON_ERROR_STOP=1 -f "{{ e2e_seed_file }}"

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
db-migrate-tests-e2e: e2e-db-guard
    @output=$(cd "{{ source_dir }}/database/migrations" && TERN_CONF="{{ e2e_tern_config }}" ./migrate.sh 2>&1); status=$?; if [ $status -ne 0 ]; then printf '%s\n' "$output"; fi; exit $status

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

# Run database tests (recreates test db, installs fixtures and runs pgTAP tests in parallel).
db-tests: db-recreate-tests db-install-tests-fixtures
    @pg_prove -h {{ db_host }} -p {{ db_port }} -d {{ db_name_tests }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -Q -j {{ num_cpus() }} -f $(find "{{ source_dir }}/database/tests/schema" "{{ source_dir }}/database/tests/functions" -type f -name '*.sql' | sort)

# Run database tests on a specific file.
db-tests-file file: db-migrate-tests db-install-tests-fixtures
    @pg_prove -h {{ db_host }} -p {{ db_port }} -d {{ db_name_tests }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -Q -f {{ file }}

# Check that function tests seed distinct unique key values (required for parallel runs).
db-tests-seed-keys: db-migrate-tests db-install-tests-fixtures
    @PGPASSWORD="{{ db_password }}" PATH="{{ pg_bin }}:$PATH" sh "{{ source_dir }}/database/scripts/check-seed-keys.sh" {{ pg_conn }} {{ db_name_tests }}

# Test upgrading representative data seeded at the schema before a migration to the latest schema.
db-migration-test version: db-drop-tests-migration db-create-tests-migration
    just pg tern migrate --migrations "{{ source_dir }}/database/migrations/schema" --host "{{ db_host }}" --port "{{ db_port }}" --user "{{ db_user }}" --database "{{ db_name_tests_migration }}" --version-table version_schema --destination "$(expr "{{ version }}" - 1)"
    just pg psql {{ pg_conn }} {{ db_name_tests_migration }} -q -v ON_ERROR_STOP=1 -f "$(ls "{{ source_dir }}"/database/tests/migrations/{{ version }}_*_seed.sql)"
    just pg tern migrate --migrations "{{ source_dir }}/database/migrations/schema" --host "{{ db_host }}" --port "{{ db_port }}" --user "{{ db_user }}" --database "{{ db_name_tests_migration }}" --version-table version_schema
    just pg tern migrate --migrations "{{ source_dir }}/database/migrations/functions" --host "{{ db_host }}" --port "{{ db_port }}" --user "{{ db_user }}" --database "{{ db_name_tests_migration }}" --version-table version_functions
    @PGPASSWORD="{{ db_password }}" pg_prove -h {{ db_host }} -p {{ db_port }} -d {{ db_name_tests_migration }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -Q -f "$(ls "{{ source_dir }}"/database/tests/migrations/{{ version }}_*.sql | grep -v '_seed\.sql$')"

# Run every representative-data migration test.
db-migration-tests:
    @for seed in "{{ source_dir }}"/database/tests/migrations/*_seed.sql; do just db-migration-test "$(basename "$seed" | cut -d_ -f1)" || exit 1; done

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
    prettier --config ocg-server/static/js/.prettierrc.yaml --write "ocg-server/static/js/**/*.js" "tests/e2e/**/*.js"
    djlint --check --configuration ocg-server/templates/.djlintrc ocg-server/templates

# Run frontend unit tests.
frontend-unit-tests:
    npm --prefix tests/unit test

# E2E

# Install e2e dependencies and Playwright browsers.
e2e-install:
    cd tests/e2e && npm ci
    cd tests/e2e && npx playwright install --with-deps

# Stamp the e2e database with a per-reset marker used by the Playwright preflight.
e2e-db-mark: e2e-db-guard
    PGPASSWORD="{{ OCG_E2E_DB_PASSWORD }}" PATH="{{ pg_bin }}:$PATH" psql {{ e2e_pg_conn }} {{ OCG_E2E_DB_NAME }} -X -q -v ON_ERROR_STOP=1 -c "update \"group\" set description = 'E2E seed run ' || gen_random_uuid()::text where group_id = '44444444-4444-4444-4444-444444444448'"

# Drop, create, migrate, seed and mark the e2e test database.
e2e-db-reset: db-recreate-tests-e2e db-load-tests-e2e-data e2e-db-mark

# Run the e2e server using cargo run (builds if needed).
e2e-server:
    just e2e-server-env cargo run -p ocg-server -- -c "{{ e2e_server_config }}"

# Run a prebuilt e2e server binary (used by CI after downloading the build artifact).
e2e-server-binary binary="target/debug/ocg-server":
    just e2e-server-env "{{ binary }}" -c "{{ e2e_server_config }}"

# Run the e2e server with watchexec for auto-reload.
e2e-server-watch:
    just e2e-server-env watchexec -r -- cargo run -p ocg-server -- -c "{{ e2e_server_config }}"

# Helper that maps the e2e database contract onto the server environment.
[private]
e2e-server-env command *args:
    OCG_DB__HOST="{{ OCG_E2E_DB_HOST }}" OCG_DB__PORT="{{ OCG_E2E_DB_PORT }}" OCG_DB__USER="{{ OCG_E2E_DB_USER }}" OCG_DB__PASSWORD="{{ OCG_E2E_DB_PASSWORD }}" OCG_DB__DBNAME="{{ OCG_E2E_DB_NAME }}" {{ command }} {{ args }}

# Run the Playwright e2e test suite (extra arguments are forwarded to Playwright).
e2e-tests *args:
    cd tests/e2e && PATH="{{ pg_bin }}:$PATH" npx playwright test --config playwright.config.js {{ args }}

# Run a single Playwright spec file (path relative to tests/e2e).
e2e-tests-file spec *args:
    cd tests/e2e && PATH="{{ pg_bin }}:$PATH" npx playwright test --config playwright.config.js "{{ spec }}" {{ args }}

# Update Playwright visual snapshots for the e2e suite.
e2e-update-snapshots:
    cd tests/e2e && PATH="{{ pg_bin }}:$PATH" npx playwright test --config playwright.config.js --project=chromium-deep --project=chromium-mobile-deep --grep @visual --update-snapshots

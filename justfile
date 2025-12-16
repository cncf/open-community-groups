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
pg_bin := env("OCG_PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
pg_conn := "-h " + db_host + " -p " + db_port + " -U " + db_user
db_server_host_opt := if db_host =~ '^/' { "-k " + db_host } else { "-h " + db_host }
source_dir := justfile_directory()

# Helper to run PostgreSQL commands with the configured binary path
[private]
pg command *args:
    PATH="{{ pg_bin }}:$PATH" {{ command }} {{ args }}

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
    PATH="{{ pg_bin }}:$PATH" psql {{ pg_conn }} {{ db_name_tests }} -c "CREATE EXTENSION IF NOT EXISTS pgtap"

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
db-tests-file file:
    pg_prove -h {{ db_host }} -p {{ db_port }} -d {{ db_name_tests }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -v {{ file }}

# Server

# Run the server using cargo run (builds if needed).
server:
    cargo run -- -c "{{ config_dir }}/server.yml"

# Build the server binary.
server-build:
    cargo build

# Format and lint server code.
server-fmt-and-lint:
    cargo fmt
    cargo check
    cargo clippy --all-targets --all-features -- --deny warnings

# Run server tests.
server-tests:
    cargo test

# Run the server with cargo watch for auto-reload.
server-watch:
    cargo watch -x "run -- -c {{ config_dir }}/server.yml"

# Frontend

# Format and lint frontend code.
frontend-fmt-and-lint:
    prettier --config ocg-server/static/js/.prettierrc.yaml --write "ocg-server/static/js/**/*.js"
    djlint --check --configuration ocg-server/templates/.djlintrc ocg-server/templates

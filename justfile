# Open Community Groups - Development Tasks
#
# Configuration: Set these environment variables
#
#   Required:
#     OCG_CONFIG  - Path to config directory
#     OCG_DATA    - Path to PostgreSQL data directory
#     OCG_PG_BIN  - Path to PostgreSQL binaries
#
#   Optional (with defaults):
#     OCG_DB_HOST       - Database host or unix socket path (default: localhost)
#     OCG_DB_NAME       - Main database name (default: ocg)
#     OCG_DB_NAME_TESTS - Test database name (default: ocg_tests)
#     OCG_DB_PORT       - Database port (default: 5432)
#     OCG_DB_SSLMODE    - SSL mode (default: disable)
#     OCG_DB_USER       - Database user (default: postgres)
#
# Please don't forget to set up the tern config files (tern.conf and tern-tests.conf) in
# the config directory (OCG_CONFIG). Make sure the database connection settings match the
# environment variables set here.

# Configuration
config_dir := env_var("OCG_CONFIG")
data_dir := env_var("OCG_DATA")
db_host := env("OCG_DB_HOST", "localhost")
db_name := env("OCG_DB_NAME", "ocg")
db_name_tests := env("OCG_DB_NAME_TESTS", "ocg_tests")
db_port := env("OCG_DB_PORT", "5432")
db_sslmode := env("OCG_DB_SSLMODE", "disable")
db_user := env("OCG_DB_USER", "postgres")
pg_bin := env_var("OCG_PG_BIN")
pg_conn := "-h " + db_host + " -U " + db_user
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
    just pg dropdb {{ pg_conn }} --if-exists {{ db_name_tests }}

# Initialize PostgreSQL data directory.
db-init:
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
db-server:
    just pg postgres -D "{{ data_dir }}"

# Run database tests (recreates test db and runs pgTAP tests).
db-tests: db-recreate-tests
    pg_prove -h {{ db_host }} -d {{ db_name_tests }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -v "{{ source_dir }}"/database/tests/{schema/*.sql,functions/**/*.sql}

# Run database tests on a specific file.
db-tests-file file:
    pg_prove -h {{ db_host }} -d {{ db_name_tests }} -U {{ db_user }} --psql-bin {{ pg_bin }}/psql -v {{ file }}

# Server

# Run the server using cargo run (builds if needed).
server:
    cargo run -- -c "{{ config_dir }}/server.yml"

# Format and lint server code, including JavaScript and templates.
server-fmt-and-lint:
    cargo fmt
    cargo clippy --all-targets --all-features -- --deny warnings
    prettier --config ocg-server/static/js/.prettierrc.yaml --write "ocg-server/static/js/**/*.js"
    djlint --check --configuration ocg-server/templates/.djlintrc ocg-server/templates

# Run server tests.
server-tests:
    cargo test

# Run the server with cargo watch for auto-reload.
server-watch:
    cargo watch -x "run -- -c {{ config_dir }}/server.yml"

#!/usr/bin/env bash
#
# Runs the chromium e2e projects with several Playwright workers, each against
# its own database and server, so workers never share state.
#
# The script builds the server, migrates and seeds a template database once
# and clones it per worker, starts one server per worker, and runs a single
# Playwright process. tests/e2e/stacks.js binds each worker to the stack
# matching its parallel index through OCG_E2E_STACKS, and the preflight checks
# every stack. Server logs are written to $TMPDIR/ocg-e2e-parallel.
#
# It expects the OCG_E2E_DB_* contract exported by the justfile and psql on
# PATH, so run it through `just e2e-tests-parallel`.
#
# Usage: parallel.sh [playwright arguments]
#   OCG_E2E_PARALLEL_WORKERS - Number of workers and stacks (default: 4)

set -euo pipefail

: "${OCG_E2E_DB_NAME:?run this script through just e2e-tests-parallel}"

base_port=9101
workers="${OCG_E2E_PARALLEL_WORKERS:-4}"
case "$workers" in
    '' | *[!0-9]* | 0)
        echo "error: OCG_E2E_PARALLEL_WORKERS must be a positive integer (got '$workers')" >&2
        exit 1
        ;;
esac

e2e_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=$(cd "$e2e_dir/../.." && pwd)
db_prefix="${OCG_E2E_DB_NAME%_e2e}_parallel"
template_db="${db_prefix}_e2e"
run_dir="${TMPDIR:-/tmp}/ocg-e2e-parallel"

stack_db() { echo "${db_prefix}_$1_e2e"; }
stack_url() { echo "http://127.0.0.1:$((base_port + $1 - 1))"; }

# Run each server in its own process group so cleanup can stop the whole tree.
set -m
pids=()
cleanup() {
    for pid in ${pids[@]+"${pids[@]}"}; do kill -- "-$pid" 2>/dev/null || true; done
    wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

cd "$source_dir"
rm -rf "$run_dir"
mkdir -p "$run_dir"

echo "==> Building server"
cargo build -p ocg-server

# Migrate and seed once, then clone the template for each stack (cheaper than migrating N times).
echo "==> Preparing $workers databases from $template_db"
OCG_E2E_DB_NAME="$template_db" just db-recreate-tests-e2e db-load-tests-e2e-data
for i in $(seq 1 "$workers"); do
    OCG_E2E_DB_NAME="$(stack_db "$i")" just db-drop-tests-e2e
    PGPASSWORD="${OCG_E2E_DB_PASSWORD:-}" createdb -h "$OCG_E2E_DB_HOST" -p "$OCG_E2E_DB_PORT" -U "$OCG_E2E_DB_USER" \
        -T "$template_db" "$(stack_db "$i")"
    OCG_E2E_DB_NAME="$(stack_db "$i")" just e2e-db-mark
done

# Keep the pools small so all servers fit within the default PostgreSQL max_connections.
echo "==> Starting $workers servers (logs in $run_dir)"
stacks=""
for i in $(seq 1 "$workers"); do
    url=$(stack_url "$i")
    OCG_DB__HOST="$OCG_E2E_DB_HOST" \
        OCG_DB__PORT="$OCG_E2E_DB_PORT" \
        OCG_DB__USER="$OCG_E2E_DB_USER" \
        OCG_DB__PASSWORD="${OCG_E2E_DB_PASSWORD:-}" \
        OCG_DB__DBNAME="$(stack_db "$i")" \
        OCG_DB__POOL__MAX_SIZE=10 \
        OCG_SERVER__ADDR="${url#http://}" \
        OCG_SERVER__BASE_URL="$url" \
        "$source_dir/target/debug/ocg-server" -c "$e2e_dir/config/server.yml" >"$run_dir/server-$i.log" 2>&1 &
    pids+=("$!")
    stacks+="${stacks:+,}{\"baseUrl\":\"$url\",\"dbName\":\"$(stack_db "$i")\"}"
done

echo "==> Running Playwright with $workers workers"
cd "$e2e_dir"
OCG_E2E_STACKS="[$stacks]" npx playwright test --config playwright.config.js \
    --project=chromium-smoke --project=chromium-deep --project=chromium-mobile-deep "$@"

#!/usr/bin/env bash
#
# Runs the chromium e2e projects with several Playwright workers, each against
# its own database and server, so workers never share state.
#
# The script builds the server (or uses a prebuilt binary), migrates and seeds
# a template database once and clones it per worker, starts one server per
# worker, and runs a single Playwright process. tests/e2e/stacks.js binds each
# worker to the stack matching its parallel index through OCG_E2E_STACKS, and
# the preflight checks every stack. Afterwards it stops the servers with SIGINT
# (no drain delay, profiles and stats are flushed), runs the post-run reports
# and exits with Playwright's status. Server logs, run-started-at, stacks.json,
# route-hits.json and db-coverage.json are written to $TMPDIR/ocg-e2e-parallel,
# and the route coverage summary is printed. With OCG_E2E_RUN_ARCHIVE set, the
# run's reports, blob report and timing are also kept there for merging with
# other runs (CI).
#
# It expects the OCG_E2E_DB_* contract exported by the justfile and psql on
# PATH, so run it through `just e2e-tests-parallel`.
#
# Usage: parallel.sh [playwright arguments]
#   Without a --project argument, the chromium-deep and chromium-mobile-deep
#   projects run.
#   OCG_E2E_PARALLEL_WORKERS - Number of workers and stacks (default: 4)
#   OCG_E2E_ROUTE_ATTRIBUTION - With 1, the route hits report joins the route
#                              attribution records the fixtures write
#   OCG_E2E_JS_COVERAGE      - With 1, the fixtures write the raw JS coverage of
#                              the Chromium projects to test-results/js-coverage/raw
#   OCG_E2E_RUN_ARCHIVE      - Folder, relative to the repository root or absolute,
#                              that receives the run folder files, the route
#                              attribution records, the raw JS coverage
#                              (js-coverage/), the blob report (blob/, CI
#                              reporter only) and run.json ({ durationSecs,
#                              exitCode, name }); its name names the run (optional)
#   OCG_E2E_SERVER_BINARY    - Prebuilt server binary, relative to the repository
#                              root or absolute (default: build target/debug/ocg-server)
#   RUST_LOG                 - Server log filter; the route hits report needs the
#                              ocg_server request span and the ocg_route_hits event
#                              (default: ocg_server=debug,ocg_route_hits=debug)

set -euo pipefail

: "${OCG_E2E_DB_NAME:?run this script through just e2e-tests-parallel}"

base_port=9101
stop_timeout_secs=30
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
# Written by the fixtures with OCG_E2E_ROUTE_ATTRIBUTION=1 (Playwright empties test-results per run).
attribution_dir="$e2e_dir/test-results/route-attribution"
# Written by the fixtures with OCG_E2E_JS_COVERAGE=1.
js_coverage_dir="$e2e_dir/test-results/js-coverage/raw"
archive_dir="${OCG_E2E_RUN_ARCHIVE:-}"
started_at=$SECONDS

# Log the route-hit event, which the default server filter leaves out.
export RUST_LOG="${RUST_LOG:-ocg_server=debug,ocg_route_hits=debug}"

stack_db() { echo "${db_prefix}_$1_e2e"; }
stack_url() { echo "http://127.0.0.1:$((base_port + $1 - 1))"; }

# Run each server in its own process group so it can be stopped as a whole.
set -m
pids=()

# Stops the servers with SIGINT, killing any that outlive stop_timeout_secs.
stop_servers() {
    local deadline=$((SECONDS + stop_timeout_secs)) pid running
    for pid in ${pids[@]+"${pids[@]}"}; do kill -INT -- "-$pid" 2>/dev/null || true; done
    while :; do
        running=()
        for pid in ${pids[@]+"${pids[@]}"}; do
            if kill -0 "$pid" 2>/dev/null; then running+=("$pid"); fi
        done
        if [ ${#running[@]} -eq 0 ]; then break; fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "warning: killing ${#running[@]} server(s) still running after ${stop_timeout_secs}s" >&2
            for pid in "${running[@]}"; do kill -KILL -- "-$pid" 2>/dev/null || true; done
            break
        fi
        sleep 0.2
    done
    wait 2>/dev/null || true
    pids=()
}

# Hook for reports built from the stopped stacks (server logs and databases).
# Every report runs even if an earlier one fails.
post_run_reports() {
    local attribution=() status=0
    if [ "${OCG_E2E_ROUTE_ATTRIBUTION:-}" = "1" ] && [ -d "$attribution_dir" ]; then
        attribution=(--attribution "$attribution_dir")
    fi
    echo "==> Writing route hits to $run_dir/route-hits.json"
    node "$e2e_dir/scripts/route-hits.js" --run-dir "$run_dir" --json "$run_dir/route-hits.json" --summary \
        ${attribution[@]+"${attribution[@]}"} || status=1
    node "$e2e_dir/scripts/route-coverage.js" --route-hits "$run_dir/route-hits.json" --summary || status=1
    echo "==> Writing DB coverage to $run_dir/db-coverage.json"
    node "$e2e_dir/scripts/db-coverage.js" --run-dir "$run_dir" --json "$run_dir/db-coverage.json" --summary ||
        status=1
    return "$status"
}

# Keeps the run folder files, the attribution records, the raw JS coverage and the timing in the
# archive folder.
archive_run() {
    local status=$1
    echo "==> Archiving the run in $archive_dir"
    cp -R "$run_dir/." "$archive_dir/"
    if [ -d "$attribution_dir" ]; then cp -R "$attribution_dir" "$archive_dir/"; fi
    if [ -d "$js_coverage_dir" ]; then cp -R "$js_coverage_dir" "$archive_dir/js-coverage"; fi
    printf '{"durationSecs":%d,"exitCode":%d,"name":"%s"}\n' "$((SECONDS - started_at))" "$status" \
        "$(basename "$archive_dir")" >"$archive_dir/run.json"
}

trap stop_servers EXIT
trap 'exit 130' INT TERM

# Start the default chromium projects unless the arguments select projects.
projects=(--project=chromium-deep --project=chromium-mobile-deep)
for arg in "$@"; do
    case "$arg" in
        --project | --project=*)
            projects=()
            break
            ;;
    esac
done

cd "$source_dir"
rm -rf "$run_dir"
mkdir -p "$run_dir"

# Each archived run writes its blob report to a folder and file of its own, so runs sharing a
# job do not delete or overwrite each other's report.
# Everything a previous run archived in the same folder is removed first, so a run that stops
# early or skips a report leaves no stale results behind.
if [ -n "$archive_dir" ]; then
    mkdir -p "$archive_dir"
    archive_dir=$(cd "$archive_dir" && pwd)
    rm -rf "$archive_dir"/{blob,js-coverage,route-attribution} "$archive_dir"/server-*.log \
        "$archive_dir"/{db-coverage.json,route-hits.json,run-started-at,run.json,stacks.json}
    PLAYWRIGHT_BLOB_OUTPUT_DIR="$archive_dir/blob"
    PLAYWRIGHT_BLOB_OUTPUT_NAME="report-$(basename "$archive_dir").zip"
    export PLAYWRIGHT_BLOB_OUTPUT_DIR PLAYWRIGHT_BLOB_OUTPUT_NAME
fi

if [ -n "${OCG_E2E_SERVER_BINARY:-}" ]; then
    if [ ! -f "$OCG_E2E_SERVER_BINARY" ] || [ ! -x "$OCG_E2E_SERVER_BINARY" ]; then
        echo "error: OCG_E2E_SERVER_BINARY is not an executable file (got '$OCG_E2E_SERVER_BINARY')" >&2
        exit 1
    fi
    server_binary="$(cd "$(dirname "$OCG_E2E_SERVER_BINARY")" && pwd)/$(basename "$OCG_E2E_SERVER_BINARY")"
    echo "==> Using prebuilt server $server_binary"
else
    echo "==> Building server"
    cargo build -p ocg-server
    server_binary="$source_dir/target/debug/ocg-server"
fi

# Migrate and seed once, then clone the template for each stack (cheaper than migrating N times).
echo "==> Preparing $workers databases from $template_db"
OCG_E2E_DB_NAME="$template_db" just db-recreate-tests-e2e db-load-tests-e2e-data
for i in $(seq 1 "$workers"); do
    OCG_E2E_DB_NAME="$(stack_db "$i")" just db-drop-tests-e2e
    PGPASSWORD="${OCG_E2E_DB_PASSWORD:-}" createdb -h "$OCG_E2E_DB_HOST" -p "$OCG_E2E_DB_PORT" -U "$OCG_E2E_DB_USER" \
        -T "$template_db" "$(stack_db "$i")"
    OCG_E2E_DB_NAME="$(stack_db "$i")" just e2e-db-mark
    # createdb -T does not copy database settings, so enable function call tracking per stack.
    OCG_E2E_DB_NAME="$(stack_db "$i")" just e2e-db-track-functions
done

# Record the start on the database clock, so reports can ignore rows written by the seed.
PGPASSWORD="${OCG_E2E_DB_PASSWORD:-}" psql -h "$OCG_E2E_DB_HOST" -p "$OCG_E2E_DB_PORT" -U "$OCG_E2E_DB_USER" \
    -X -q -A -t -v ON_ERROR_STOP=1 -d "$template_db" \
    -c "select to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')" \
    >"$run_dir/run-started-at"

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
        "$server_binary" -c "$e2e_dir/config/server.yml" >"$run_dir/server-$i.log" 2>&1 &
    pids+=("$!")
    stacks+="${stacks:+,}{\"baseUrl\":\"$url\",\"dbName\":\"$(stack_db "$i")\"}"
done
echo "[$stacks]" >"$run_dir/stacks.json"

echo "==> Running Playwright with $workers workers"
cd "$e2e_dir"
set +e
OCG_E2E_STACKS="[$stacks]" npx playwright test --config playwright.config.js \
    ${projects[@]+"${projects[@]}"} "$@"
status=$?
set -e

echo "==> Stopping servers"
stop_servers

post_run_reports || echo "warning: post-run reports failed" >&2
if [ -n "$archive_dir" ]; then archive_run "$status" || echo "warning: archiving the run failed" >&2; fi

exit "$status"

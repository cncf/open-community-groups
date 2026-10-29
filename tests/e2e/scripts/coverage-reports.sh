#!/usr/bin/env bash
#
# Merges the coverage reports of several archived e2e runs (OCG_E2E_RUN_ARCHIVE
# in parallel.sh), such as the CI shards: route hits from every server log and
# attribution folder, route coverage against the manifest and allowlist, and
# DB function coverage summed from every db-coverage.json. The reports are
# written to OUT_DIR (route-hits.json, route-coverage.json, db-coverage.json)
# and their summaries to stdout and OUT_DIR/summary.txt.
#
# Every report runs even if an earlier one fails; the script exits non-zero
# when any of them failed. The checks are non-blocking: uncovered routes and
# functions are only listed.
#
# Usage: coverage-reports.sh RUNS_DIR OUT_DIR
#   RUNS_DIR - Folder with one archived run per subfolder
#   OUT_DIR  - Folder for the merged reports (created if missing)

set -uo pipefail

if [ $# -ne 2 ]; then
    echo "usage: coverage-reports.sh RUNS_DIR OUT_DIR" >&2
    exit 2
fi

runs_dir=$1
out_dir=$2
scripts_dir=$(cd "$(dirname "$0")" && pwd)

if [ ! -d "$runs_dir" ]; then
    echo "error: $runs_dir is not a folder" >&2
    exit 1
fi
mkdir -p "$out_dir"

# Collect the inputs of every run; runs that stopped early may lack some of them.
logs=()
attribution=()
db_reports=()
for run in "$runs_dir"/*/; do
    if compgen -G "${run}server-*.log" >/dev/null; then logs+=("$run"); fi
    if [ -d "${run}route-attribution" ]; then attribution+=(--attribution "${run}route-attribution"); fi
    if [ -f "${run}db-coverage.json" ]; then db_reports+=(--merge "${run}db-coverage.json"); fi
done

status=0
{
    if [ ${#logs[@]} -eq 0 ]; then
        echo "error: no run in $runs_dir has server logs" >&2
        status=1
    else
        node "$scripts_dir/route-hits.js" --json "$out_dir/route-hits.json" --summary \
            ${attribution[@]+"${attribution[@]}"} "${logs[@]}" || status=1
        node "$scripts_dir/route-coverage.js" --route-hits "$out_dir/route-hits.json" \
            --json "$out_dir/route-coverage.json" --summary || status=1
    fi
    if [ ${#db_reports[@]} -eq 0 ]; then
        echo "error: no run in $runs_dir has a db-coverage.json" >&2
        status=1
    else
        node "$scripts_dir/db-coverage.js" "${db_reports[@]}" --json "$out_dir/db-coverage.json" --summary ||
            status=1
    fi
    exit "$status"
} 2>&1 | tee "$out_dir/summary.txt"

#!/bin/sh
#
# Checks database layer conventions that migrations and the function loader
# cannot enforce on their own.
#
# Trigger function rules:
#   - Every trigger function created by a schema migration has a source file
#     under functions/triggers/ and is listed in the function loader, unless a
#     later schema migration dropped it.
#   - Schema migrations newer than the sweep migration may only define the
#     first body of a new trigger function; later body changes belong to the
#     loader copy only.
#   - create trigger statements live in schema migrations, never in loader
#     function files.
#
# Layout rules:
#   - Every function file has a mirrored pgTAP test at the same path under
#     tests/functions, and every test under tests/functions mirrors a function
#     file (scenario-split test files named <function>_<suffix>.sql and the
#     payments/refund_worker_lifecycle.sql lifecycle suite are allowed).
#   - Functions under functions/internal/ are SQL-only helpers: the Rust
#     crates never call them (contract tests excepted).
#
# Test rules:
#   - pgTAP function tests run in parallel against one database, so they must
#     not take table-level locks (alter table, lock table, truncate).
#   - Fixture functions (fx_*) are installed by the test recipes only; nothing
#     under migrations/ may reference them.
#   - Each function test owns its UUID prefix (the first segment of its \set
#     identifiers); two files sharing a prefix would insert the same primary
#     keys and block or deadlock each other when run in parallel.

set -u

database_dir=$(cd "$(dirname "$0")/.." && pwd)
functions_dir="$database_dir/migrations/functions"
schema_dir="$database_dir/migrations/schema"
tests_dir="$database_dir/tests"
loader_file="$functions_dir/001_load_functions.sql"
triggers_dir="$functions_dir/triggers"
sweep_migration=0079

status=0

fail() {
    echo "error: $1" >&2
    status=1
}

# Every function file has a mirrored test, and every test mirrors a function
for file in $(cd "$functions_dir" && find . -name '*.sql' ! -name '001_load_functions.sql' | sed 's|^\./||' | sort); do
    if [ ! -f "$tests_dir/functions/$file" ]; then
        fail "$functions_dir/$file has no mirrored test at $tests_dir/functions/$file"
    fi
done
for file in $(cd "$tests_dir/functions" && find . -name '*.sql' | sed 's|^\./||' | sort); do
    if [ -f "$functions_dir/$file" ]; then
        continue
    fi
    case "$file" in
        payments/refund_worker_lifecycle.sql) continue ;; # cross-function lifecycle suite
    esac
    dir=$(dirname "$file")
    base=$(basename "$file" .sql)
    matched=0
    for candidate in "$functions_dir/$dir"/*.sql; do
        name=$(basename "$candidate" .sql)
        case "$base" in
            "${name}_"*) matched=1; break ;;
        esac
    done
    if [ "$matched" -eq 0 ]; then
        fail "$tests_dir/functions/$file does not mirror a function file under $functions_dir/$dir"
    fi
done

# Functions under internal/ are SQL-only helpers and must not be called from Rust
for file in $(find "$functions_dir/internal" -name '*.sql' | sort); do
    name=$(basename "$file" .sql)
    callers=$(grep -rlE "\b$name\b" "$database_dir/../ocg-server/src" "$database_dir/../ocg-redirector/src" --include='*.rs' \
        | grep -v '/contract_tests/' || true)
    if [ -n "$callers" ]; then
        fail "internal function $name is referenced from Rust: $(printf '%s' "$callers" | tr '\n' ' ')"
    fi
done

# Prints "migration_number function_name" for every trigger function defined
# by a schema migration.
trigger_function_definitions() {
    for file in "$schema_dir"/*.sql; do
        number=$(basename "$file" | cut -d_ -f1)
        awk -v number="$number" '
            match($0, /create (or replace )?function [a-z_]+\(\)/) {
                name = substr($0, RSTART, RLENGTH)
                sub(/.*function /, "", name)
                sub(/\(\)/, "", name)
                pending = name
                if ($0 ~ /returns trigger/) { print number, name; pending = "" }
                next
            }
            pending != "" && /returns trigger/ { print number, pending; pending = "" }
            pending != "" && !/^[[:space:]]*$/ { pending = "" }
        ' "$file"
    done
}

# Prints every trigger function name dropped by a schema migration.
dropped_trigger_functions() {
    grep -hoE 'drop function if exists [a-z_]+\(\)' "$schema_dir"/*.sql \
        | sed 's/drop function if exists //; s/()//' \
        | sort -u
}

definitions=$(trigger_function_definitions)
dropped=$(dropped_trigger_functions)

# Live trigger functions need a loader source file and a loader entry
for name in $(printf '%s\n' "$definitions" | awk '{ print $2 }' | sort -u); do
    if printf '%s\n' "$dropped" | grep -qx "$name"; then
        continue
    fi
    if [ ! -f "$triggers_dir/$name.sql" ]; then
        fail "trigger function $name is defined in a schema migration but has no $triggers_dir/$name.sql"
    fi
    if ! grep -q "{{ template \"triggers/$name.sql\" }}" "$loader_file"; then
        fail "trigger function $name is not listed in $loader_file"
    fi
done

# Migrations after the sweep may only define a trigger function's first body
redefinitions=$(printf '%s\n' "$definitions" | awk -v sweep="$sweep_migration" '
    {
        if (seen[$2] != "" && $1 > sweep) {
            printf "%s redefined in migration %s (first defined in %s)\n", $2, $1, seen[$2]
        }
        if (seen[$2] == "") { seen[$2] = $1 }
    }
')
if [ -n "$redefinitions" ]; then
    printf '%s\n' "$redefinitions" | while read -r line; do
        echo "error: trigger function $line; change the body in $triggers_dir instead" >&2
    done
    status=1
fi

# Loader function files must not create triggers
for file in $(find "$functions_dir" -name '*.sql' -exec grep -lE 'create (constraint )?trigger ' {} +); do
    fail "$file creates a trigger; create trigger statements belong to schema migrations"
done

# Function tests run in parallel and must not take table-level locks
for file in $(find "$tests_dir/functions" -name '*.sql' -exec grep -liE '^[[:space:]]*(alter table|lock table|truncate) ' {} +); do
    fail "$file takes a table-level lock; function tests run in parallel and must stay transactional"
done

# Function tests must not share UUID prefixes
shared_prefixes=$(grep -rHoE '\\set [A-Za-z0-9_]+ '"'"'[0-9a-f]{8}-0000-0000-0000-' "$tests_dir/functions" --include='*.sql' \
    | sed -E "s/^([^:]+):.*'([0-9a-f]{8})-.*/\2 \1/" \
    | sort -u \
    | awk '{ files[$1] = files[$1] " " $2; count[$1]++ } END { for (p in count) if (count[p] > 1) print p ":" files[p] }' \
    | sort)
if [ -n "$shared_prefixes" ]; then
    printf '%s\n' "$shared_prefixes" | while read -r line; do
        echo "error: UUID prefix ${line%%:*} is used by more than one function test:${line#*:}" >&2
    done
    status=1
fi

# Fixture functions are test-only
for file in $(find "$database_dir/migrations" -name '*.sql' -exec grep -lE '\bfx_[a-z_]+\(' {} +); do
    fail "$file references a test fixture function; fx_* functions are installed by the test recipes only"
done

if [ "$status" -eq 0 ]; then
    echo "database lint passed"
fi
exit "$status"

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

set -u

database_dir=$(cd "$(dirname "$0")/.." && pwd)
functions_dir="$database_dir/migrations/functions"
schema_dir="$database_dir/migrations/schema"
loader_file="$functions_dir/001_load_functions.sql"
triggers_dir="$functions_dir/triggers"
sweep_migration=0079

status=0

fail() {
    echo "error: $1" >&2
    status=1
}

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

if [ "$status" -eq 0 ]; then
    echo "database lint passed"
fi
exit "$status"

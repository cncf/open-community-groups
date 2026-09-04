#!/bin/sh
#
# Checks that no two pgTAP function tests write the same unique key value.
#
# The suite runs in parallel against one database. Two files inserting the same
# value into a unique index block each other until one rolls back, and a pair
# doing that for two values in opposite order deadlocks. Every function test
# therefore owns its unique key values (usernames, emails, community names,
# provider references, idempotency keys, ...), just as it owns its UUID prefix.
#
# For every unique index in the migrated test database, the script runs each
# file with its final rollback deferred, reads the indexed values written by
# the seed and by the tests themselves, rolls back, and fails when a value
# appears in more than one file.
#
# Usage: check-seed-keys.sh <psql connection arguments>
#   e.g. check-seed-keys.sh -h localhost -p 5432 -U postgres ocg_tests

set -u

tests_dir=$(cd "$(dirname "$0")/../tests/functions" && pwd)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# Build one query returning (index, value) for every unique index
key_query=$(psql "$@" -qtAX -v ON_ERROR_STOP=1 <<'SQL'
with unique_indexes as (
    select
        i.indexrelid::regclass::text as index_name,
        i.indrelid::regclass::text as table_name,
        i.indnkeyatts as key_count,
        regexp_replace(pg_get_indexdef(i.indexrelid), '^.* using btree \((.*?)\)( where .*)?$', '\1', 'i') as key_columns,
        nullif(regexp_replace(pg_get_indexdef(i.indexrelid), '^.* using btree \(.*?\)( where (.*))?$', '\2', 'i'), '') as predicate
    from pg_index i
    join pg_class c on c.oid = i.indrelid
    join pg_namespace n on n.oid = c.relnamespace
    where i.indisunique
    and n.nspname = 'public'
    and c.relname not like 'version_%'
    -- Singleton configuration rows are shared by design
    and c.relname <> 'external_payments_config'
)
select string_agg(
    format(
        'select %L as key, concat_ws(''|'', %s)::text as val from %s where num_nonnulls(%s) = %s%s',
        index_name,
        key_columns,
        table_name,
        key_columns,
        key_count,
        coalesce(' and ' || predicate, '')
    ),
    E'\nunion all\n'
    order by index_name
)
from unique_indexes;
SQL
)
if [ -z "$key_query" ]; then
    echo "error: could not build the unique key query from the database catalog" >&2
    exit 1
fi

# Keys already present before any seed (reference data) are not owned by a file
printf '%s;\n' "$key_query" | psql "$@" -qtAX -v ON_ERROR_STOP=1 | sort -u >"$workdir/baseline"

status=0
: >"$workdir/keys"
for file in $(find "$tests_dir" -name '*.sql' | sort); do
    # Run the whole file with its rollback deferred, then read the written keys
    {
        sed '/^rollback;$/d' "$file"
        printf '\\echo __KEYS__\n%s;\nrollback;\n' "$key_query"
    } | psql "$@" -qtAX -v ON_ERROR_STOP=1 2>"$workdir/error" \
        | sed -n '/^__KEYS__$/,$p' | grep '|' | sort -u | comm -23 - "$workdir/baseline" \
        | sed "s|^|${file#"$tests_dir"/}\t|" >>"$workdir/keys"
    if [ -s "$workdir/error" ]; then
        echo "error: ${file#"$tests_dir"/}: $(head -n 1 "$workdir/error")" >&2
        status=1
    fi
done

# Report every (index, value) seeded by more than one file
duplicates=$(sort -u "$workdir/keys" | awk -F '\t' '
    { files[$2] = files[$2] " " $1; count[$2]++ }
    END { for (key in count) if (count[key] > 1) print key ":" files[key] }
' | sort)
if [ -n "$duplicates" ]; then
    printf '%s\n' "$duplicates" | while read -r line; do
        echo "error: unique key ${line%%:*} is seeded by more than one function test:${line#*:}" >&2
    done
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "seed keys check passed"
fi
exit "$status"

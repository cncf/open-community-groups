#!/bin/sh
#
# Checks database layer conventions that migrations and the function loader
# cannot enforce on their own.
#
# Schema migration rules:
#   - Any migration using CONCURRENTLY must include the exact Tern directive
#     line '---- tern: disable-tx ----', and malformed disable-tx directives
#     are rejected.
#   - Schema migrations newer than the concurrent-index cutoff migration must
#     use CONCURRENTLY for indexes created on existing relations (tables or
#     materialized views not created in the same migration).
#   - Non-transactional ('---- tern: disable-tx ----') migrations must not use
#     SET LOCAL or mix table DDL (CREATE/ALTER/DROP TABLE); they must set
#     session-level lock_timeout and statement_timeout before DDL and reset
#     both at the end of the migration.
#   - Every CREATE [UNIQUE] INDEX CONCURRENTLY <name> must be immediately
#     preceded by DROP INDEX CONCURRENTLY IF EXISTS <name>.
#
# Trigger function rules:
#   - Every trigger function created by a schema migration has a source file
#     under functions/triggers/ and is listed in the function loader, unless a
#     later schema migration dropped it.
#   - Schema migrations newer than the sweep migration may only define the
#     first body of a new trigger function; later body changes belong to the
#     loader copy only.
#   - create [or replace] [constraint] trigger statements live in schema
#     migrations, never in loader function files.
#
# Layout rules:
#   - Every function file has a mirrored pgTAP test at the same path under
#     tests/functions, and every test under tests/functions mirrors a function
#     file (the payments/refund_worker_lifecycle.sql lifecycle suite excepted).
#   - A scenario-split test file named <function>_<suffix>.sql states its base
#     and reason within its first three lines with a
#     "-- Split from <function>.sql because|to ..." header.
#   - Functions under functions/internal/ are SQL-only helpers: the Rust
#     crates never call them (contract tests excepted).
#   - Every test under tests/schema/constraints is named after a table created
#     or renamed by a schema migration.
#   - Every language sql function declares its volatility (immutable, stable
#     or volatile) on its language line.
#   - The visibility predicates called from parallel-planned reads
#     (is_event_listed, is_event_public, is_group_public) stay parallel safe.
#
# Test rules:
#   - pgTAP schema and function tests run in parallel against one database, so
#     they must not take table-level locks (alter table, lock table, truncate,
#     create [or replace] [constraint] trigger, drop trigger). A create
#     trigger statement is allowed only when its target is a session-local
#     table created with create temporary table in the same file.
#   - Fixture functions (fx_*) are installed by the test recipes only; nothing
#     under migrations/ may reference them.
#   - Each parallel test owns its UUID prefix (the first segment of its \set
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
# Last migration exempt from the post-cutoff concurrent index requirement
concurrent_index_cutoff=0107

schema_only=0
if [ "${1:-}" = "--schema-dir" ]; then
    if [ -z "${2:-}" ] || [ ! -d "$2" ]; then
        echo "error: --schema-dir requires an existing directory" >&2
        exit 1
    fi
    schema_dir=$2
    schema_only=1
elif [ $# -gt 0 ]; then
    echo "usage: $0 [--schema-dir <dir>]" >&2
    exit 1
fi

status=0

fail() {
    echo "error: $1" >&2
    status=1
}

# Check non-transactional and concurrent-index rules across schema migrations
check_schema_migrations() {
    for file in "$schema_dir"/*.sql; do
        [ -f "$file" ] || continue
        number=$(basename "$file" | cut -d_ -f1)
        if ! awk -v file="$file" -v number="$number" -v cutoff="$concurrent_index_cutoff" '
            function normalize_ident(raw, s) {
                s = tolower(raw)
                gsub(/"/, "", s)
                sub(/^public\./, "", s)
                return s
            }
            function is_positive_timeout(stmt, val) {
                val = stmt
                sub(/^set (session )?(lock_timeout|statement_timeout) *(= *|to )/, "", val)
                gsub(/^[ \047]+|[ \047]+$/, "", val)
                if (val == "" || val == "default") {
                    return 0
                }
                if (val !~ /^[0-9]+(\.[0-9]+)? *(us|ms|s|min|h|d)?$/) {
                    return 0
                }
                return (val ~ /[1-9]/)
            }
            function push_stmt(raw, s) {
                s = raw
                gsub(/[ \t\r\n]+/, " ", s)
                sub(/^ /, "", s)
                sub(/ $/, "", s)
                if (s != "") {
                    stmt_count++
                    stmts[stmt_count] = s
                }
            }
            BEGIN {
                err = 0
                sq = "\047"
                in_down = 0
                has_disable_tx = 0
                in_sq = 0
                in_esq = 0
                in_dq = 0
                bc_depth = 0
                dollar_tag = ""
                cur = ""
                stmt_count = 0
            }
            {
                if (!in_sq && !in_dq && dollar_tag == "" && bc_depth == 0) {
                    if ($0 == "---- create above / drop below ----") {
                        in_down = 1
                        next
                    }
                    if (in_down) {
                        next
                    }
                    if ($0 == "---- tern: disable-tx ----") {
                        has_disable_tx = 1
                        next
                    }
                    low_raw = tolower($0)
                    if (low_raw ~ /^[ \t]*--+[ \t]*tern[ \t]*:.*disable/ \
                        || low_raw ~ /^[ \t]*---+[ \t]*tern[ \t]*:/ \
                        || low_raw ~ /^[ \t]*\/\*[ \t]*tern[ \t]*:.*disable/ \
                        || low_raw ~ /^[ \t]*---+.*disable[-_ ]?tx/) {
                        printf "error: %s has a malformed disable-tx directive; use the exact line '\''---- tern: disable-tx ----'\''\n", file > "/dev/stderr"
                        err = 1
                    }
                } else if (in_down) {
                    next
                }

                line = $0
                len = length(line)
                for (i = 1; i <= len; i++) {
                    ch = substr(line, i, 1)
                    ch2 = substr(line, i, 2)

                    if (bc_depth > 0) {
                        if (ch2 == "/*") {
                            bc_depth++
                            i++
                        } else if (ch2 == "*/") {
                            bc_depth--
                            i++
                            cur = cur " "
                        }
                        continue
                    }

                    if (dollar_tag != "") {
                        if (substr(line, i, length(dollar_tag)) == dollar_tag) {
                            cur = cur dollar_tag
                            i += length(dollar_tag) - 1
                            dollar_tag = ""
                        } else {
                            cur = cur ch
                        }
                        continue
                    }

                    if (in_sq) {
                        cur = cur ch
                        if (in_esq && ch == "\\") {
                            if (i < len) {
                                i++
                                cur = cur substr(line, i, 1)
                            }
                            continue
                        }
                        if (ch == sq) {
                            if (substr(line, i + 1, 1) == sq) {
                                cur = cur sq
                                i++
                            } else {
                                in_sq = 0
                                in_esq = 0
                            }
                        }
                        continue
                    }

                    if (in_dq) {
                        cur = cur ch
                        if (ch == "\"") {
                            if (substr(line, i + 1, 1) == "\"") {
                                cur = cur "\""
                                i++
                            } else {
                                in_dq = 0
                            }
                        }
                        continue
                    }

                    if (ch2 == "--") {
                        break
                    }
                    if (ch2 == "/*") {
                        bc_depth = 1
                        i++
                        continue
                    }
                    if (ch == sq) {
                        in_sq = 1
                        in_esq = (i >= 2 && substr(line, i - 1, 1) ~ /^[eE]$/ && (i < 3 || substr(line, i - 2, 1) !~ /[A-Za-z0-9_$]/))
                        cur = cur ch
                        continue
                    }
                    if (ch == "\"") {
                        in_dq = 1
                        cur = cur ch
                        continue
                    }
                    if (ch == "$") {
                        if (match(substr(line, i), /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/)) {
                            dollar_tag = substr(line, i, RLENGTH)
                            cur = cur dollar_tag
                            i += RLENGTH - 1
                            continue
                        }
                    }
                    if (ch == ";") {
                        push_stmt(cur)
                        cur = ""
                        continue
                    }
                    cur = cur ch
                }
                if (!in_sq && !in_dq && dollar_tag == "" && bc_depth == 0) {
                    cur = cur " "
                }
            }
            END {
                push_stmt(cur)

                is_post_cutoff = (number ~ /^[0-9]+$/ && (number + 0) > (cutoff + 0))
                uses_concurrently = 0
                seen_set_lock = 0
                seen_set_stmt = 0
                seen_reset_lock = 0
                seen_reset_stmt = 0
                work_before_timeouts = 0
                stmt_after_reset = 0

                for (i = 1; i <= stmt_count; i++) {
                    s = tolower(stmts[i])

                    is_create_table = (s ~ /^create ((global|local) )?((temporary|temp|unlogged) )?table /)
                    if (is_create_table) {
                        rest = s
                        sub(/^create ((global|local) )?((temporary|temp|unlogged) )?table (if not exists )?/, "", rest)
                        if (match(rest, /^[^ (]+/)) {
                            created_relations[normalize_ident(substr(rest, RSTART, RLENGTH))] = 1
                        }
                    } else if (s ~ /^create materialized view /) {
                        rest = s
                        sub(/^create materialized view (if not exists )?/, "", rest)
                        if (match(rest, /^[^ (]+/)) {
                            created_relations[normalize_ident(substr(rest, RSTART, RLENGTH))] = 1
                        }
                    }

                    is_create_conc = (s ~ /^create (unique )?index concurrently( |$)/)
                    is_drop_conc = (s ~ /^drop index concurrently( |$)/)
                    is_reindex_conc = (s ~ /^reindex (index|table|schema|database|system) concurrently( |$)/ \
                        || s ~ /^reindex ?\([^)]*\) (index|table|schema|database|system) concurrently( |$)/ \
                        || s ~ /^reindex ?\(([^)]*[^a-z0-9_])?concurrently([^a-z0-9_][^)]*)?\)/)
                    if (is_create_conc || is_drop_conc || is_reindex_conc) {
                        uses_concurrently = 1
                    }

                    if (is_post_cutoff && !is_create_conc && s ~ /^create (unique )?index /) {
                        if (match(s, / on (only )?[^ (]+/)) {
                            target = substr(s, RSTART, RLENGTH)
                            sub(/^ on (only )?/, "", target)
                            tbl = normalize_ident(target)
                            if (!(tbl in created_relations)) {
                                printf "error: %s creates an index on existing table %s without CONCURRENTLY; use a separate '\''---- tern: disable-tx ----'\'' migration with DROP INDEX CONCURRENTLY IF EXISTS and CREATE INDEX CONCURRENTLY\n", file, tbl > "/dev/stderr"
                                err = 1
                            }
                        }
                    }

                    if (is_create_conc) {
                        rest = s
                        sub(/^create (unique )?index concurrently /, "", rest)
                        sub(/^if not exists /, "", rest)
                        idx_name = ""
                        if (match(rest, /^[^ (]+/)) {
                            idx_name = substr(rest, RSTART, RLENGTH)
                        }
                        if (idx_name == "" || idx_name == "on") {
                            printf "error: %s has an unnamed CREATE INDEX CONCURRENTLY; name the index and precede it with DROP INDEX CONCURRENTLY IF EXISTS <name>\n", file > "/dev/stderr"
                            err = 1
                        } else {
                            norm_idx = normalize_ident(idx_name)
                            prev = (i > 1 ? tolower(stmts[i - 1]) : "")
                            drop_ok = 0
                            if (prev ~ /^drop index concurrently if exists [^ ,]+$/) {
                                drop_name = prev
                                sub(/^drop index concurrently if exists /, "", drop_name)
                                if (normalize_ident(drop_name) == norm_idx) {
                                    drop_ok = 1
                                }
                            }
                            if (!drop_ok) {
                                printf "error: %s runs CREATE INDEX CONCURRENTLY %s without an immediately preceding DROP INDEX CONCURRENTLY IF EXISTS %s\n", file, norm_idx, norm_idx > "/dev/stderr"
                                err = 1
                            }
                        }
                    }

                    if (has_disable_tx) {
                        if (s ~ /^set local /) {
                            printf "error: %s uses SET LOCAL under '\''---- tern: disable-tx ----'\''; PostgreSQL ignores SET LOCAL outside a transaction block (use session-level SET with trailing RESET)\n", file > "/dev/stderr"
                            err = 1
                            continue
                        }

                        if (is_create_table || s ~ /^alter table / || s ~ /^drop table /) {
                            printf "error: %s mixes table DDL into a '\''---- tern: disable-tx ----'\'' migration; move table/column DDL to a separate transactional migration\n", file > "/dev/stderr"
                            err = 1
                        }

                        is_set_lock = (s ~ /^set (session )?lock_timeout *(= *|to )[^ ]/)
                        is_set_stmt = (s ~ /^set (session )?statement_timeout *(= *|to )[^ ]/)
                        is_reset_lock = (s ~ /^reset lock_timeout$/)
                        is_reset_stmt = (s ~ /^reset statement_timeout$/)
                        is_set = (s ~ /^set /)
                        is_reset = (s ~ /^reset /)

                        if ((seen_reset_lock || seen_reset_stmt) && !is_reset) {
                            stmt_after_reset = 1
                        }
                        if (is_set_lock) {
                            if (!is_positive_timeout(s)) {
                                printf "error: %s sets lock_timeout to a non-positive or default value under '\''---- tern: disable-tx ----'\''; specify a positive bound\n", file > "/dev/stderr"
                                err = 1
                            }
                            seen_set_lock = 1
                        } else if (is_set_stmt) {
                            if (!is_positive_timeout(s)) {
                                printf "error: %s sets statement_timeout to a non-positive or default value under '\''---- tern: disable-tx ----'\''; specify a positive bound\n", file > "/dev/stderr"
                                err = 1
                            }
                            seen_set_stmt = 1
                        } else if (is_reset_lock) {
                            seen_reset_lock = 1
                        } else if (is_reset_stmt) {
                            seen_reset_stmt = 1
                        } else if (!is_set && !is_reset) {
                            if (!seen_set_lock || !seen_set_stmt) {
                                work_before_timeouts = 1
                            }
                        }
                    }
                }

                if (uses_concurrently && !has_disable_tx) {
                    printf "error: %s uses CONCURRENTLY without the exact '\''---- tern: disable-tx ----'\'' directive\n", file > "/dev/stderr"
                    err = 1
                }

                if (has_disable_tx) {
                    if (!seen_set_lock || !seen_set_stmt) {
                        printf "error: %s uses '\''---- tern: disable-tx ----'\'' without session-level SET lock_timeout and SET statement_timeout\n", file > "/dev/stderr"
                        err = 1
                    } else if (work_before_timeouts) {
                        printf "error: %s must set lock_timeout and statement_timeout before DDL statements under '\''---- tern: disable-tx ----'\''\n", file > "/dev/stderr"
                        err = 1
                    }
                    if (!seen_reset_lock || !seen_reset_stmt) {
                        printf "error: %s uses '\''---- tern: disable-tx ----'\'' without trailing RESET lock_timeout and RESET statement_timeout\n", file > "/dev/stderr"
                        err = 1
                    } else if (stmt_after_reset) {
                        printf "error: %s must place RESET lock_timeout and RESET statement_timeout after all DDL statements\n", file > "/dev/stderr"
                        err = 1
                    }
                }

                exit err
            }
        ' "$file"; then
            status=1
        fi
    done
}

check_schema_migrations

if [ "$schema_only" -eq 1 ]; then
    if [ "$status" -eq 0 ]; then
        echo "database schema migration lint passed"
    fi
    exit "$status"
fi

# Every function file has a mirrored test, and every test mirrors a function
# or is a scenario split that names its base file in its header
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
    headed=0
    header=$(head -n 3 "$tests_dir/functions/$file")
    for candidate in "$functions_dir/$dir"/*.sql; do
        name=$(basename "$candidate" .sql)
        case "$base" in
            "${name}_"*)
                matched=1
                # A sibling may prefix-match several functions; any of them may be its base
                if printf '%s\n' "$header" | grep -qE "^-- Split from $name\.sql (because|to) "; then
                    headed=1
                fi
                ;;
        esac
    done
    if [ "$matched" -eq 0 ]; then
        fail "$tests_dir/functions/$file does not mirror a function file under $functions_dir/$dir"
    elif [ "$headed" -eq 0 ]; then
        fail "$tests_dir/functions/$file is a scenario split without a '-- Split from <function>.sql because|to ...' header in its first 3 lines"
    fi
done

# Constraint tests are named after the table whose constraints they exercise
for file in $(find "$tests_dir/schema/constraints" -name '*.sql' | sort); do
    table=$(basename "$file" .sql)
    if ! grep -qE "^(create table (if not exists )?\"?$table\"? \(|alter table \"?[a-z_]+\"? rename to \"?$table\"?;)" "$schema_dir"/*.sql; then
        fail "$file is not named after a table created or renamed by a schema migration"
    fi
done

# Every language sql function declares its volatility on its language line
unmarked=$(grep -rnE '\blanguage sql\b' "$functions_dir" --include='*.sql' \
    | grep -v "^$loader_file:" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*--' \
    | grep -vE '\b(immutable|stable|volatile)\b')
if [ -n "$unmarked" ]; then
    printf '%s\n' "$unmarked" | cut -d: -f1-2 | while read -r location; do
        echo "error: $location: language sql function without a volatility marker" >&2
    done
    status=1
fi

# Visibility predicates called from parallel-planned reads stay parallel safe
for file in internal/events/is_event_listed.sql internal/events/is_event_public.sql internal/groups/is_group_public.sql; do
    if ! grep -qE '^\$\$ language sql [a-z]+ parallel safe;$' "$functions_dir/$file"; then
        fail "$functions_dir/$file must stay parallel safe; parallel-planned reads call it"
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
for file in $(find "$functions_dir" -name '*.sql' -exec grep -lE 'create (or replace )?(constraint )?trigger ' {} +); do
    fail "$file creates a trigger; create trigger statements belong to schema migrations"
done

# Parallel tests must not take table-level locks; create trigger is allowed
# only on a temporary table created in the same file
table_lock_pattern='^[[:space:]]*(alter table|lock table|truncate|drop trigger) '
create_trigger_pattern='create (or replace )?(constraint )?trigger '
for file in $(find "$tests_dir/schema" "$tests_dir/functions" -name '*.sql' -exec grep -liE "$table_lock_pattern|$create_trigger_pattern" {} +); do
    if grep -qiE "$table_lock_pattern" "$file"; then
        fail "$file takes a table-level lock; pgTAP tests run in parallel and must stay transactional"
        continue
    fi
    # Join statements onto one line, without comments, and check every target
    statements=$(sed 's/--.*$//' "$file" | tr '\n' ' ' | tr -s ' ')
    temporary_tables=$(printf '%s\n' "$statements" \
        | grep -ioE 'create (temporary|temp) table (if not exists )?[a-z_][a-z0-9_]*' \
        | awk '{ print tolower($NF) }')
    printf '%s\n' "$statements" \
        | grep -ioE "${create_trigger_pattern}[^;]*(;|\$)" \
        | while read -r statement; do
            target=$(printf '%s\n' "$statement" | awk '{ for (i = 1; i < NF; i++) if (tolower($i) == "on") { t = tolower($(i + 1)); sub(/;$/, "", t); print t; exit } }')
            if [ -z "$target" ] || ! printf '%s\n' "$temporary_tables" | grep -qxF "$target"; then
                echo "$statement"
            fi
        done \
        | grep -q . \
        && fail "$file creates a trigger on a table it did not create as temporary; pgTAP tests run in parallel and must stay transactional"
done

# Parallel tests must not share UUID prefixes
shared_prefixes=$(grep -rHoE '\\set [A-Za-z0-9_]+ '"'"'[0-9a-f]{8}-0000-0000-0000-' "$tests_dir/schema" "$tests_dir/functions" --include='*.sql' \
    | sed -E "s/^([^:]+):.*'([0-9a-f]{8})-.*/\2 \1/" \
    | sort -u \
    | awk '{ files[$1] = files[$1] " " $2; count[$1]++ } END { for (p in count) if (count[p] > 1) print p ":" files[p] }' \
    | sort)
if [ -n "$shared_prefixes" ]; then
    printf '%s\n' "$shared_prefixes" | while read -r line; do
        echo "error: UUID prefix ${line%%:*} is used by more than one test:${line#*:}" >&2
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

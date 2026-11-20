#!/bin/sh
#
# Self-tests for schema migration lint rules in database/scripts/lint.sh.

set -eu

scripts_dir=$(cd "$(dirname "$0")" && pwd)
lint_script="$scripts_dir/lint.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

failures=0

run_case() {
    name=$1
    expected=$2
    filename=$3
    expected_msg=${4:-}
    case_dir="$workdir/$name"
    mkdir -p "$case_dir"
    cat >"$case_dir/$filename"

    if output=$(sh "$lint_script" --schema-dir "$case_dir" 2>&1); then
        rc=0
    else
        rc=$?
    fi

    if [ "$expected" = "pass" ] && [ "$rc" -ne 0 ]; then
        echo "FAIL ($name): expected pass, got exit $rc" >&2
        printf '%s\n' "$output" >&2
        failures=$((failures + 1))
    elif [ "$expected" = "fail" ] && [ "$rc" -eq 0 ]; then
        echo "FAIL ($name): expected failure, but lint passed" >&2
        failures=$((failures + 1))
    elif [ "$expected" = "fail" ] && [ -n "$expected_msg" ] && ! printf '%s\n' "$output" | grep -qF -- "$expected_msg"; then
        echo "FAIL ($name): expected stderr containing '$expected_msg', got:" >&2
        printf '%s\n' "$output" >&2
        failures=$((failures + 1))
    fi
}

# Valid non-transactional concurrent index migration (single, unique, prose comment, E-string)
run_case valid_concurrent_index pass 0108_add_concurrent_index.sql <<'SQL'
-- Adds concurrent indexes on existing tables (uses tern: disable-tx for non-blocking builds).
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';

drop index concurrently if exists event_foo_idx;
create index concurrently event_foo_idx
    on event (foo)
    where deleted = false and note <> E'it\'s; -- ok';

drop index concurrently if exists group_bar_idx;
create unique index concurrently group_bar_idx on "group" (bar);

reset lock_timeout;
reset statement_timeout;
SQL

# Valid transactional migration adding a new table with a non-concurrent index and SET LOCAL
run_case valid_new_table_index pass 0108_add_new_table.sql <<'SQL'
-- Adds a new table and its index in one transaction.

set local lock_timeout = '5s';
set local statement_timeout = '10min';

create table widget (
    widget_id uuid primary key,
    created_at timestamptz not null,
    note text default 'keep -- and ; inside quotes'
);

create index widget_created_at_idx on widget (created_at);
SQL

# Valid transactional migration adding a materialized view and its index
run_case valid_new_matview_index pass 0108_add_matview.sql <<'SQL'
-- Tern: applied by migrate.sh before functions.

create materialized view event_summary_mv as
select event_id from event;

create unique index event_summary_mv_event_id_idx on event_summary_mv (event_id);
SQL

# Valid migration with directive-like text inside a multi-line string literal
run_case valid_directive_text_in_string pass 0108_string_literal.sql <<'SQL'
-- Stores multiline documentation text mentioning tern directives.

update config set docs = 'example:
-- tern: disable-tx
done';
SQL

# Valid pre-cutoff migration with non-concurrent index on an existing table
run_case valid_pre_cutoff_index pass 0107_legacy_index.sql <<'SQL'
-- Pre-cutoff migration remains exempt from post-cutoff concurrent index requirement.

create index event_legacy_idx on event (foo);
SQL

# Valid concurrent index drop without recreate
run_case valid_concurrent_drop pass 0108_drop_old_index.sql <<'SQL'
-- Drops an obsolete index concurrently.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';

drop index concurrently if exists old_idx;

reset lock_timeout;
reset statement_timeout;
SQL

# Isolated malformed disable-tx directive without CONCURRENTLY (wrong dash count)
run_case malformed_disable_tx_dashes fail 0108_bad_directive.sql "has a malformed disable-tx directive" <<'SQL'
-- Uses malformed directive without CONCURRENTLY.
-- tern: disable-tx

select 1;
SQL

# Isolated malformed disable-tx directive without CONCURRENTLY (missing space)
run_case malformed_disable_tx_spacing fail 0108_bad_spacing.sql "has a malformed disable-tx directive" <<'SQL'
-- Uses malformed directive spacing.
---- tern:disable-tx ----

select 1;
SQL

# CONCURRENTLY without disable-tx directive
run_case missing_disable_tx fail 0108_missing_disable_tx.sql "uses CONCURRENTLY without the exact '---- tern: disable-tx ----' directive" <<'SQL'
-- Adds a concurrent index without disabling transactions.

drop index concurrently if exists event_foo_idx;
create index concurrently event_foo_idx on event (foo);
SQL

# REINDEX (CONCURRENTLY) without disable-tx directive
run_case reindex_concurrently_without_disable_tx fail 0108_reindex_conc.sql "uses CONCURRENTLY without the exact '---- tern: disable-tx ----' directive" <<'SQL'
-- Reindexes concurrently without disabling transactions.

reindex (verbose, concurrently) table event;
SQL

# REINDEX (VERBOSE) TABLE CONCURRENTLY without disable-tx directive
run_case reindex_option_table_concurrently_without_disable_tx fail 0108_reindex_opt_conc.sql "uses CONCURRENTLY without the exact '---- tern: disable-tx ----' directive" <<'SQL'
-- Reindexes concurrently with leading parenthesized options without disabling transactions.

reindex (verbose) table concurrently event;
SQL

# Isolated SET LOCAL under disable-tx (valid session timeouts present so only SET LOCAL fails)
run_case set_local_under_disable_tx fail 0108_set_local.sql "uses SET LOCAL under '---- tern: disable-tx ----'" <<'SQL'
-- Uses SET LOCAL under disable-tx alongside valid session timeouts.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';
set local work_mem = '64MB';

drop index concurrently if exists event_foo_idx;
create index concurrently event_foo_idx on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# Mixing table DDL into a disable-tx migration is rejected
run_case table_ddl_under_disable_tx fail 0108_table_ddl_disable_tx.sql "mixes table DDL into a '---- tern: disable-tx ----' migration" <<'SQL'
-- Mixes ALTER TABLE into a non-transactional migration.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';

alter table event add column extra text;
drop index concurrently if exists event_extra_idx;
create index concurrently event_extra_idx on event (extra);

reset lock_timeout;
reset statement_timeout;
SQL

# Zero timeout disables the bound and is rejected under disable-tx
run_case zero_lock_timeout fail 0108_zero_lock_timeout.sql "sets lock_timeout to a non-positive or default value" <<'SQL'
-- Disables lock_timeout with 0 under disable-tx.
---- tern: disable-tx ----

set lock_timeout = 0;
set statement_timeout = '10min';

drop index concurrently if exists event_foo_idx;
create index concurrently event_foo_idx on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# Zero timeout with units or DEFAULT is rejected under disable-tx
run_case zero_statement_timeout fail 0108_zero_stmt_timeout.sql "sets statement_timeout to a non-positive or default value" <<'SQL'
-- Disables statement_timeout with '0s' under disable-tx.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '0s';

drop index concurrently if exists event_foo_idx;
create index concurrently event_foo_idx on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# Missing session-level timeouts under disable-tx
run_case missing_timeouts fail 0108_missing_timeouts.sql "without session-level SET lock_timeout and SET statement_timeout" <<'SQL'
-- Omits session timeouts under disable-tx.
---- tern: disable-tx ----

drop index concurrently if exists event_foo_idx;
create index concurrently event_foo_idx on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# DDL placed before session-level timeouts under disable-tx
run_case ddl_before_timeouts fail 0108_ddl_before_timeouts.sql "must set lock_timeout and statement_timeout before DDL statements" <<'SQL'
-- Places DDL before setting timeouts.
---- tern: disable-tx ----

drop index concurrently if exists event_foo_idx;
set lock_timeout = '5s';
set statement_timeout = '10min';
create index concurrently event_foo_idx on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# Missing trailing RESET under disable-tx
run_case missing_reset fail 0108_missing_reset.sql "without trailing RESET lock_timeout and RESET statement_timeout" <<'SQL'
-- Omits trailing RESET statements under disable-tx.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';

drop index concurrently if exists event_foo_idx;
create index concurrently event_foo_idx on event (foo);
SQL

# RESET placed before DDL under disable-tx
run_case reset_before_ddl fail 0108_reset_before_ddl.sql "must place RESET lock_timeout and RESET statement_timeout after all DDL statements" <<'SQL'
-- Resets timeouts before creating the index.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';
reset lock_timeout;
reset statement_timeout;

drop index concurrently if exists event_foo_idx;
create index concurrently event_foo_idx on event (foo);
SQL

# CREATE INDEX CONCURRENTLY without preceding DROP INDEX CONCURRENTLY IF EXISTS
run_case create_without_drop fail 0108_create_without_drop.sql "without an immediately preceding DROP INDEX CONCURRENTLY IF EXISTS event_foo_idx" <<'SQL'
-- Relies on IF NOT EXISTS alone instead of DROP INDEX CONCURRENTLY IF EXISTS.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';

create index concurrently if not exists event_foo_idx on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# Unnamed CREATE INDEX CONCURRENTLY
run_case create_unnamed fail 0108_create_unnamed.sql "has an unnamed CREATE INDEX CONCURRENTLY" <<'SQL'
-- Omits the index name.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';

create index concurrently on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# CREATE INDEX CONCURRENTLY preceded by DROP INDEX for a different index name
run_case create_drop_name_mismatch fail 0108_name_mismatch.sql "without an immediately preceding DROP INDEX CONCURRENTLY IF EXISTS event_foo_idx" <<'SQL'
-- Drops a different index than the one created.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';

drop index concurrently if exists other_idx;
create index concurrently event_foo_idx on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# CREATE INDEX CONCURRENTLY preceded by DROP INDEX CONCURRENTLY without IF EXISTS
run_case create_drop_without_if_exists fail 0108_drop_no_if_exists.sql "without an immediately preceding DROP INDEX CONCURRENTLY IF EXISTS event_foo_idx" <<'SQL'
-- Drops concurrently without IF EXISTS.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';

drop index concurrently event_foo_idx;
create index concurrently event_foo_idx on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# CREATE INDEX CONCURRENTLY preceded by non-concurrent DROP INDEX
run_case create_drop_not_concurrent fail 0108_drop_not_concurrent.sql "without an immediately preceding DROP INDEX CONCURRENTLY IF EXISTS event_foo_idx" <<'SQL'
-- Drops non-concurrently before concurrent create.
---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '10min';

drop index if exists event_foo_idx;
create index concurrently event_foo_idx on event (foo);

reset lock_timeout;
reset statement_timeout;
SQL

# Non-concurrent CREATE INDEX on an existing table in a post-sweep migration
run_case non_concurrent_existing_table fail 0108_non_concurrent_existing.sql "creates an index on existing table event without CONCURRENTLY" <<'SQL'
-- Creates a write-blocking index on an existing table.

create index event_foo_idx on event (foo);
SQL

# Single-quoted literal containing '--' must not swallow the following non-concurrent index
run_case single_quote_dash_dash_not_comment fail 0108_sq_dash_dash.sql "creates an index on existing table event without CONCURRENTLY" <<'SQL'
-- Ensures single-quoted strings with '--' do not mask later statements.

update event set note = 'see -- docs';
create index event_foo_idx on event (foo);
SQL

if [ "$failures" -ne 0 ]; then
    echo "database lint self-tests failed: $failures failure(s)" >&2
    exit 1
fi

echo "database lint self-tests passed"

# Database layer

This document describes how the PostgreSQL layer of Open Community Groups is
organized and the conventions every change to it follows. Business logic lives
in PostgreSQL functions; the Rust server calls them through thin wrappers and
consumes their results as typed DTOs.

## Folder layout

```text
database/
  migrations/
    schema/       Numbered Tern migrations: tables, indexes, constraints,
                  reference data, triggers, drop statements
    functions/    Function sources loaded by 001_load_functions.sql
      auth/, common/, community/, dashboard-*/, event/, group/,
      meetings/, notifications/, payments/, site/, triggers/
    migrate.sh    Applies schema migrations, then reloads every function
  scripts/
    lint.sh       Convention checks run by `just db-lint` and CI
  tests/
    schema/       pgTAP catalog tests (tables, columns, keys, indexes,
                  functions, triggers, constraints, reference data)
    functions/    pgTAP tests mirroring migrations/functions one to one
    data/         Deterministic seeds for contract (contract.sql) and
                  end-to-end (e2e.sql) databases
    migrations/   Representative-data upgrade tests
```

Function folders mirror the Rust database traits in `ocg-server/src/db`:
a function called from `db/dashboard/group.rs` lives in
`functions/dashboard-group/`, one called from `db/payments.rs` in
`functions/payments/`, and so on. `common/` holds functions shared by several
traits together with SQL-only helpers (validators, projections, search
scaffolding). `triggers/` holds every trigger function. Every function file
has a mirrored test at the same path under `tests/functions/`.

## Loader ordering

`functions/001_load_functions.sql` is a single Tern migration that loads every
function with `{{ template "<folder>/<file>.sql" }}` entries. Entries are
grouped by folder and alphabetized within the group. A function that depends
on another function being defined first is placed after its dependency and
carries a short trailing comment naming the dependency (`-- Dependency for
...` or `-- Do not sort alphabetically, has dependency`).

`migrate.sh` applies schema migrations first and then re-runs the loader on
every migration run, so the loader copy of a function is always the live
definition after a deploy.

## Migrations and drop rules

- Schema migrations are numbered and descriptive
  (`0079_add_audit_log_mutation_guard.sql`) and start with a one-line purpose
  comment.
- Function bodies live in `functions/` only. A schema migration never
  contains `create or replace function` for a Rust-facing or SQL-only
  function.
- Changing a function's parameters or return type requires a `drop function`
  statement in a numbered schema migration; the function source file only
  contains `create or replace function`.
- `create trigger` statements live in schema migrations (see
  [Trigger functions](#trigger-functions)).
- Every schema change updates the catalog tests under `tests/schema/` in the
  same change.

## Error contract

Database functions signal failures with `raise exception`, and the SQLSTATE
decides who sees the message:

- **User-facing rejections** raise with `using errcode = 'OCG01'`. The Rust
  `HandlerError` maps `OCG01` to HTTP 422 with the message as the response
  body. Use it whenever a legitimate request can hit the condition: stale
  forms, conflicting enrollment state, invalid payloads, missing resources,
  features not configured on the server.
- **Internal invariant failures** use the default `P0001`. The Rust layer
  treats them as internal errors (HTTP 500) and never shows the message to
  users. This covers worker and queue mechanics (claims, retry limits,
  configuration checks), provider webhook consistency checks, `p_*_id is
  null` contract checks, `else` branches for unreachable enum values, slug or
  username exhaustion, trigger immutability guards, and SQL-only helpers whose
  callers validate before delegating.
- Rust maps by SQLSTATE only. Handlers never match on message text.
- `detail` may carry a stable machine-readable code when a client needs to
  distinguish rejections programmatically; the message alone is enough for
  the common case.
- PL/pgSQL callers that translate expected rejections catch them with
  `when sqlstate 'OCG01'`, never with `when others`.
- Messages are short, lowercase, and domain-readable
  (`event not found or inactive`); pgTAP asserts them together with the
  SQLSTATE: `throws_ok(sql, 'OCG01', 'message', description)` for user-facing
  rejections, `throws_ok(sql, 'message', description)` for internal ones.

### Conflict results

`prepare_event_checkout_purchase`, `invite_event_attendee`, and
`accept_event_invitation_request` return `jsonb_build_object('conflict',
'<code>')` instead of raising for outcomes where the caller must keep going
(the checkout flow reuses pending purchases, falls back to admission-offer
snapshots, or queues the user). Use this shape only when the Rust caller has
a next step after the conflict; everywhere else, raise with the error
contract.

## Authorization rule

- Rust route middleware is the authorization boundary.
  `user_has_path_group_permission`, `user_has_path_community_permission`,
  `user_has_selected_group_permission`, and
  `user_has_selected_community_permission` run before any dashboard handler,
  and `ocg-server/src/router/tests.rs` asserts that every community and group
  dashboard mutation route rejects a read-only user.
- SQL functions enforce scope and state, not permissions: parent/child
  ownership (`event.group_id`, `group.community_id`), active/deleted/canceled
  flags, row ownership (`p_user_id`), and invariants under locks.
- `p_actor_user_id` identifies the actor for audit rows and ownership. It is
  never used to look up permissions.
- `user_has_group_permission` and `user_has_community_permission` may be
  called from SQL only to answer a domain question about a *different*
  resource than the one the route authorized (the new parent group in
  `update_group` and `add_group`, the parent options in
  `list_group_parent_options`) or to compute notification recipients
  (`request_event_refund`).

## Trigger functions

- The schema migration that creates a trigger defines the trigger function's
  first body, so `create trigger` resolves, and the same function is added to
  `functions/triggers/` in the same change.
- All later body changes go to the `functions/triggers/` copy only. A trigger
  function is never redefined in a later schema migration; the loader would
  overwrite that body on the next migration run.
- `create trigger` statements stay in schema migrations. Loader files never
  create triggers.
- Each trigger function has a test under `tests/functions/triggers/`.
- `database/scripts/lint.sh` (`just db-lint`, also run in CI) enforces these
  rules: every schema-defined trigger function has a loader file and a
  loader entry, no trigger function is defined by more than one schema
  migration after `0079`, and no loader file creates a trigger.

## Job lifecycles

Background work is coordinated through database state so that workers can be
restarted safely and external calls stay outside transactions:

- **Claim**: a worker takes a row with `for update skip locked` and records a
  claim identity and timestamp (`claim_pending_notification`,
  `claim_meeting_out_of_sync`, `claim_meeting_for_auto_end`,
  `claim_badge_award_job`, `claim_event_purchase_refund`,
  `claim_event_purchase_credit_note`,
  `claim_event_purchase_application_fee_adjustment`).
- **Outcome**: the worker records success, a retryable failure, or a terminal
  failure against its claim (`update_notification`, `requeue_notification`,
  `set_meeting_error`, `set_meeting_auto_end_check_outcome`,
  `record_badge_award_job_failure`, `record_event_purchase_refund_*`,
  `record_event_purchase_credit_note_*`,
  `record_event_purchase_application_fee_adjustment_*`). Stale claims are
  rejected so a delayed worker cannot overwrite a newer attempt.
- **Stale claim recovery**: periodic functions release claims whose worker
  disappeared (`mark_stale_processing_notifications_unknown`,
  `mark_stale_meeting_syncs_unknown`,
  `mark_stale_meeting_auto_end_checks_unknown`,
  `recover_stale_badge_award_jobs`,
  `requeue_stale_event_purchase_*_claims`).
- **Operator recovery**: exhausted payment work can be retried
  (`requeue_event_purchase_*`) or completed with external evidence
  (`complete_event_purchase_*_recovery`) from the group dashboard.
- Idempotency keys and provider references are stored before any external
  side effect so retries and webhooks can be reconciled.

## Inline SQL in Rust

Trivial single-table reads and writes may stay inline in `ocg-server/src/db`:
the `auth_session` and `images` tables, `get_event_purchase_charge_model`,
`get_group_payment_recipient`, `get_payment_provider_tax_location`, and the
`pg_timezone_names` and `attachment` lookups. Anything with a join, a branch,
or a domain rule (a status filter, a soft-delete flag, ownership) lives in a
function with a mirrored pgTAP test.

## Tests

### pgTAP function tests

- Every function file has a test at the same path under `tests/functions/`;
  changing a function updates its test in the same change.
- Files start with a `-- Tests <purpose>.` comment and use the sections
  `SETUP`, `VARIABLES`, `SEED DATA`, `TESTS`, `CLEANUP` in that order,
  wrapped in `begin; ... rollback;` with an exact `plan` count.
- Variables use deterministic UUIDs with a per-file prefix and are
  alphabetized.
- `SEED DATA` builds prerequisite state with commented `insert` statements,
  ordered by foreign-key dependency and then by table name; each scenario gets
  its own rows rather than mutating shared ones.
- `TESTS` only invokes the behavior under test and asserts persisted state.
  Direct writes appear in `TESTS` only when the write itself is the behavior
  under test (constraints and triggers).
- A test asserts only values it wrote itself.
- Rejections assert the SQLSTATE and message as described in the
  [error contract](#error-contract).

### Schema tests

`tests/schema/` asserts the catalog: tables and extensions, columns, keys,
indexes, functions and triggers, constraints and reference data. Every
migration updates the relevant file.

### Rust contract tests

`ocg-server/src/db/contract_tests.rs` runs the ignored `db_contracts` tests
against a real database migrated and seeded with `tests/data/contract.sql`.
They guard the JSON boundary between functions and Rust DTOs, lock ordering,
and the error SQLSTATEs. A change to a JSON-returning function, a DTO, a
wrapper, or `contract.sql` runs `just db-contract-tests`.

### Commands

```nu
just db-lint
just db-tests
just db-tests-file database/tests/functions/<folder>/<function>.sql
just db-contract-tests
just db-migration-tests
```

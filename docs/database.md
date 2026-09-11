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
      internal/<concern>/   SQL-only helpers, never called from Rust
      auth/, common/, community/, dashboard-*/, event/, group/,
      images/, meetings/, notifications/, payments/, redirector/,
      site/                 Rust-facing functions, one folder per trait
      triggers/             Trigger functions
    migrate.sh    Applies schema migrations, then reloads every function
  scripts/
    lint.sh       Convention checks run by `just db-lint` and CI
  tests/
    schema/       pgTAP catalog tests (tables, columns, keys, indexes,
                  functions, triggers, constraints, reference data)
    functions/    pgTAP tests mirroring migrations/functions one to one
    fixtures/     fx_* fixture functions installed into the test database
                  by the test recipes, never by the application loader
    data/         Deterministic seeds for contract (contract.sql) and
                  end-to-end (e2e.sql) databases
    migrations/   Representative-data upgrade tests
```

Rust-facing function folders mirror the database traits in `ocg-server/src/db`
(and `ocg-redirector/src/db.rs` for `redirector/`): a function called from
`db/dashboard/group.rs` lives in `functions/dashboard-group/`, one called from
`db/payments.rs` in `functions/payments/`, and so on. `common/` holds only the
`DBCommon` trait functions. `triggers/` holds every trigger function.
Operator-only entry points documented for `psql` use
(`requeue_badge_award_job`, `manual_requeue_notifications`) stay in the folder
of the feature they serve.

Helpers that are only called from other SQL functions live under
`functions/internal/<concern>/`, grouped coarsely by the rule they own:
`audit`, `enrollment`, `events`, `groups`, `json`, `meetings`,
`notifications`, `payments`, `search`, `stats`, `text`, `ticketing`, `users`.
The path answers "is this a contract change?": a signature or result shape
under `internal/` may change freely as long as its SQL callers and tests are
updated in the same change; anything outside `internal/` is consumed by Rust
and requires the DTO, wrapper and contract-test updates described below.
`database/scripts/lint.sh` fails when an `internal/` function name appears in
Rust code (contract tests excepted).

Every function file has a mirrored test at the same path under
`tests/functions/` and the lint script checks the mirror in both directions.

## Loader ordering

`functions/001_load_functions.sql` is a single Tern migration that loads every
function with `{{ template "<folder>/<file>.sql" }}` entries. The
`internal/<concern>/` groups load first (alphabetically by concern), then the
Rust-facing folders alphabetically; entries are alphabetized within each
group. Only `language sql` bodies are resolved at creation time, so ordering
exceptions exist solely for a `language sql` function whose dependency would
otherwise load later. Such an entry is moved next to its dependency and
carries a trailing comment (`-- Dependency for <callers>` when pulled
forward, `-- Depends on <function>` when pushed back); `plpgsql` callers need
no exception.

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

### Trust model

These rules describe conventions inside one trust boundary, not enforcement
the database provides on its own:

- A database function trusts its caller to have authorized the actor. Given a
  matching `p_group_id` or `p_community_id`, a mutation acts for any
  `p_actor_user_id` it is handed; the actor is an audit identity, not proof of
  permission. Every entry point that calls these functions (today: the Rust
  server behind its route middleware, plus the operator-only functions run
  through `psql` by a database administrator) is responsible for that
  authorization. A second service, an administrative API or a job runner that
  calls the functions directly must authorize before it calls, and the route
  test in `ocg-server/src/router/tests.rs` covers only the routes of this
  server.
- `functions/internal/` is a layout and lint convention. Any role that can
  execute the Rust-facing functions can execute the helpers too; the folder
  answers "is this a contract change?", it does not isolate database access.

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
  migration after `0079`, and no loader file creates a trigger. It also
  checks the layout rules (function/test mirror in both directions, no
  `internal/` function referenced from Rust) and the test rules below: no
  table-level locks in function tests and no `fx_*` references under
  `migrations/`.

## Job lifecycles

Background work is coordinated through database state so that workers can be
restarted safely and external calls stay outside transactions:

- **Claim**: a worker takes a row with `for update skip locked` and records a
  claim identity and timestamp (`claim_pending_notification`,
  `claim_meeting_out_of_sync`, `claim_meeting_for_auto_end`,
  `claim_badge_award_job`, `claim_payment_job`).
- **Outcome**: the worker records success, a retryable failure, or a terminal
  failure against its claim (`update_notification`, `requeue_notification`,
  `set_meeting_error`, `set_meeting_auto_end_check_outcome`,
  `record_badge_award_job_failure`, `record_payment_job_failure`,
  `record_event_purchase_refund_*`,
  `record_event_purchase_credit_note_succeeded`,
  `record_event_purchase_application_fee_adjustment_succeeded`). Stale claims
  are rejected so a delayed worker cannot overwrite a newer attempt.
- **Release**: a worker interrupted by shutdown between attempts returns its
  claim to the queue without recording an outcome (`release_notification`):
  the row goes back to `pending`, becomes claimable immediately, and keeps
  its `delivery_attempts` and `error`, so a restart does not spend the retry
  budget or mark the notification `failed` on its last claim. The same stale
  claim guard applies.
- **Stale claim recovery**: periodic functions release claims whose worker
  disappeared (`mark_stale_processing_notifications_unknown`,
  `mark_stale_meeting_syncs_unknown`,
  `mark_stale_meeting_auto_end_checks_unknown`,
  `recover_stale_badge_award_jobs`, `requeue_stale_payment_job_claims`).
- **Operator recovery**: exhausted payment work can be retried
  (`requeue_payment_job`) or completed with external evidence
  (`complete_payment_job_recovery`,
  `complete_event_purchase_refund_recovery`) from the group dashboard.
- Idempotency keys and provider references are stored before any external
  side effect so retries and webhooks can be reconciled.

### Payment jobs

Every provider-mediated payment task (customer refund, credit note,
application-fee adjustment) is one row in `payment_job` plus one typed domain
row (`event_purchase_refund`, `event_purchase_credit_note`,
`event_purchase_application_fee_adjustment`) that references it through
`payment_job_id`. The job owns the worker mechanics only: `kind`,
`payment_provider_id`, `event_purchase_id` (the purchase every kind hangs off,
used for group scoping), `idempotency_key`, `status` (`pending`, `processing`,
`failed`, `completed`), `attempt_count`, `next_attempt_at`, `claim_id` and
`claimed_at`, `failure_message`, `completed_at` and the `recovery_*` evidence.
The domain row keeps every typed outcome: the refund's provider status machine
(`provider-pending`, `provider-succeeded`, `provider-failed` with
`terminal_failure`, `finalized`), `provider_credit_note_id`,
`provider_application_fee_refund_id`, amounts and references. No `jsonb`
payload column exists.

- Domain functions create work with `enqueue_payment_job(kind, provider,
  purchase, idempotency_key)`, which returns `null` when the key already
  exists so the domain insert is skipped; the idempotency key is the only
  duplicate guard (`event-purchase-refund-<purchase>`,
  `event-purchase-credit-note-<refund>`,
  `event-purchase-refund-fee-adjustment-<purchase>`,
  `event-purchase-tax-fee-adjustment-<purchase>`).
- `claim_payment_job(kind, provider)` claims due work whose domain row is
  ready (`payment_job_is_ready`: the purchase has its provider application fee,
  the refund behind a credit note is provider-confirmed, the refund is not
  pinned to a terminal failure), increments `attempt_count`, and returns
  `payment_job_to_json(job) || payment_job_payload(job)`: the lifecycle fields
  plus one nested object (`refund`, `credit_note`,
  `application_fee_adjustment`) with the provider context of that kind. Every
  claim counts toward `payment_job_max_attempts()` (10), including refund
  finalization attempts; `record_event_purchase_refund_succeeded` resets the
  count so finalization gets a fresh budget once the provider confirms.
  `requeue_stale_payment_job_claims` releases an expired claim as `failed` and
  keeps `attempt_count`, so abandoned claims spend the budget and the job
  reaches exhaustion; only `record_event_purchase_refund_succeeded` and the
  operator retry (`requeue_payment_job`) reset it.
- Success paths write the typed outcome first
  (`apply_event_purchase_*_outcome`, the refund `finalized_at`) and then call
  `complete_payment_job(job, claim)`. A successful replay must either
  establish that the job is already `completed` or complete the outstanding
  bookkeeping through `complete_payment_job` under its claim rules; it never
  repeats the domain side effects. The credit-note and fee-adjustment
  recorders check the job status; `finalize_event_purchase_refund` checks
  `status = 'finalized'` on the refund (not `finalized_at`, which a terminal
  provider failure keeps as history) and completes the job from that branch,
  as `record_event_purchase_refund_succeeded` does when `finalized_at` is
  set. Two trigger functions keep the
  invariant "a `completed` job has its outcome on the domain row" in both
  directions: `check_payment_job_completion_outcome` runs before a job is
  updated to `completed` and, as a deferred constraint trigger, after a
  `completed` job is inserted directly (so a job and its domain row can be
  created in one transaction); `check_payment_job_domain_outcome` runs before
  every insert or update of the three domain tables and rejects a row whose
  job is `completed` while its outcome is null. Retryable failures call
  `record_payment_job_failure` (bounded backoff via
  `payment_job_retry_delay`); a refund that the provider reports as failed
  stays `failed` on the job and `provider-failed`/`terminal_failure` on the
  refund until an operator recovers it. A terminal failure reported after
  finalization re-opens the completed job.
- `payment_job_is_exhausted(job)` (`failed` or `pending` with
  `attempt_count >= payment_job_max_attempts()`) is the single definition of
  "needs an operator" used by `requeue_payment_job`,
  `complete_payment_job_recovery`, `list_group_refunds` and
  `search_event_attendees`.
- Notifications, meetings and badges keep their own queue tables and claim
  functions.

## Shared predicates and helpers

Each domain rule has one home under `functions/internal/`; callers delegate
instead of repeating the predicate, so the rule cannot drift between files.
The rule-owning helpers are:

- `event_effective_ends_at(event)`: `coalesce(ends_at, starts_at)`, the moment
  an event stops being current (an event with a start and no end is over once
  it starts).
- `lock_active_event(p_community_id, p_group_id, p_event_id,
  p_require_published)`: locks (`for update`) an event scoped by community
  and/or group whose group is active and which is not deleted, canceled or
  over (optionally published), raising `event not found or inactive`
  (`OCG01`). Every attendee and organizer enrollment mutation starts with it.
- `lock_active_group(p_community_id, p_group_id)`: locks a non-deleted group
  in the community, raising `group not found or inactive` (`OCG01`); the
  `active` flag is not required because activation is one of the mutations.
- `admission_offer_is_active(status)` (`checkout_pending`, `pending`) and
  `event_purchase_holds_seat(status)` (`completed` and the refund-in-flight
  states): the status sets that reserve capacity.
- `event_has_pending_refund_recovery(p_event_id, p_user_id,
  p_excluded_event_purchase_id)`: another purchase of the user awaits operator
  refund recovery, which blocks new checkouts.
- `event_user_enrollment(p_event_id, p_user_id)`: one row with the attendee
  row, active admission offer, relevant purchase, refund request, invitation
  request and waitlist facts for a user, plus a derived `state`
  (`confirmed`, `payment-pending`, `offer-active`, `registration-pending`,
  `invitation-pending`, `invitation-declined`, `approval-pending`,
  `approval-rejected`, `waitlisted`, `offer-expired`, `none`). Read functions
  map the state to their labels; mutations lock their rows first and then
  read the facts from it.
- `parse_search_filters(p_filters)` and `prefix_tsquery(config, text)`: the
  pagination (`limit`/`offset`, clamped to non-negative, null when absent),
  `ts_query` (trimmed, as an ILIKE pattern and as a `simple` prefix-matching
  tsquery), `date_from`/`date_to` and lowercased `sort` keys shared by
  `search_*` and `list_*` functions. Callers keep their defaults, sort
  allow-lists and function-specific keys.
- Projections and encodings: `epoch_seconds(timestamptz)` (whole seconds,
  truncated; the only timestamp encoding in JSON results),
  `public_user_summary("user")`, `event_venue_snapshot(event)`,
  `event_purchase_refund_to_json(event_purchase_refund, payment_job)`,
  `payment_job_to_json(payment_job)` and
  `event_ticket_type_current_price(event_ticket_type_id)`.
- `release_meeting_sync(p_event_id, p_session_id, p_sync_claimed_at,
  p_sync_state_hash, p_error)`: completes a meeting sync claim for the
  `add/update/delete_meeting` and `set_meeting_error` workers.
- `event_accepts_enrollment(event, "group")`: the row-based form of the
  `lock_active_event` predicate (active group; published, not deleted, not
  canceled, not over) for callers that already hold the rows.
- `lock_event_enrollment_rows(p_event_id, p_event_ticket_type_id, p_user_id)`:
  the global enrollment lock order after the event row (ticket tiers, one
  advisory lock per affected user, active offers, pending purchases), shared
  by the reconciliation functions.
- Event payload resolution: `resolve_event_payload(p_event, p_before,
  p_group_external_ready)` parses, merges and normalizes the event columns,
  ticket types and discount codes written by `add_event` (null prior row) and
  `update_event` (locked prior row), delegating rail selection to
  `resolve_event_payment_rail`; `validate_event_payment_validation` binds the
  server's provider validation snapshot to the locked group recipient.
- Organizer offers: `resolve_organizer_offer_expiry(event)`,
  `validate_admission_offer_payment_readiness(event, "group", amount,
  provider)` and `admission_offer_capacity_conflict(event_ticket_type,
  promoted_user_ids)` are shared by `invite_event_attendee` and
  `accept_event_invitation_request`.
- Purchase completion: `complete_event_purchase_admission_offer`,
  `confirm_event_purchase_attendee` and `mark_event_purchase_refund_pending`
  are the single homes of the offer, attendee and refund-pending transitions
  used by the checkout webhook and the free and external completion flows.

Extract by meaning, not by size or repetition alone. A predicate, status set
or projection gets a named helper here when it encodes a domain rule with
more than one home, so that the rule cannot drift; a short sequence with a
single caller stays inline when reading it in place needs less context than
following a call. When a change touches the second occurrence of such a rule,
extract it and delegate from the occurrences the change already reads;
sweeping every other occurrence is a follow-up, not a requirement of the
change. The test of a good extraction is that a contributor can understand
and safely change the workflow with less context, not that the caller became
shorter.

## Prior state, row types and phases

- **Write paths read prior state from rows.** A mutation locks the rows it
  changes (`select e.* into v_event from event e ... for update of e`) and
  passes `%rowtype` values (`event`, `"group"`, `session`, `event_purchase`,
  `admission_offer`, `event_ticket_type`) to its helpers. Public JSON
  projections (`get_event_full`, ...) are read models for Rust and are never
  used as the prior state of a write. A Rust-facing function that needs prior
  state takes identifiers and reads the row itself
  (`event_ticketing_configuration_changed(p_community_id, p_group_id,
  p_event_id, p_event)`).
  Association rows read as prior state (`event_host`, `event_speaker`,
  `session_speaker`) must still be unchanged when the comparison runs:
  `update_event` derives the event meeting sync inside its row update and
  synchronizes sessions before `sync_event_hosts_speakers_sponsors` replaces
  the hosts.
- **Payload timestamps are compared at whole seconds.** Helpers that compare
  a stored timestamp with one parsed from a payload
  (`is_event_meeting_in_sync`, `is_session_meeting_in_sync`,
  `validate_update_event_dates`) truncate the stored value with
  `date_trunc('second', ...)`, the precision `epoch_seconds` gives the
  dashboard, so a round-tripped value never reads as a change.
- **Composites use `returns table`.** No named composite types exist; a
  helper returning several values declares `returns table (...)` and callers
  `select * into v_record` and copy composite columns into `%rowtype` locals
  (`v_event := v_payload.resolved`). A column of a row type is read with
  parentheses in SQL (`(r.resolved).name`).
- **Large mutations are split on phase boundaries.** An orchestrator keeps
  the lock order and the decisions; a phase (validate, protect, mutate,
  confirm, audit, return) moves to an `internal/` helper that takes the locked
  rows when it is a unit a reader wants to name and reason about on its own or
  when another flow needs the same transition, not merely because it is long.
  Phases with one caller and a few statements stay inline
  (`finalize_event_purchase_refund` keeps its attendance, purchase and request
  updates; `record_event_purchase_refund_succeeded` keeps its two enqueues).
  The split flows are: `reconcile_event_enrollment`
  delegates to `lock_event_enrollment_rows`, `expire_event_checkout_holds`,
  `remind_event_external_payment_holds`, `reconcile_event_admission_offers`
  and `promote_event_waitlist_entries`;
  `reconcile_event_purchase_for_checkout_session` to
  `validate_direct_charge_checkout_amounts`,
  `record_direct_charge_checkout_amounts` and the purchase completion helpers;
  `prepare_event_checkout_purchase` to `load_checkout_context`,
  `prepare_event_checkout_resolve_offer_pricing` and
  `prepare_event_checkout_lookup_tax_cache`. Helpers that build notification
  data shared by several phases (`external_payment_notification_payload`)
  live next to them.

### Test ownership when extracting helpers

- Every helper has its own test under `tests/functions/internal/<concern>/`
  covering its full branch matrix. Callers do not repeat that matrix.
- A caller's test keeps every scenario that proves the caller's own decisions
  (state transitions, audit rows, returned payload, label mapping) and at
  least one wiring scenario per delegated rejection, proving the helper is
  called and its error propagates.
- Helpers can each be correct while their ordering, inputs or combined state
  transitions are wrong, so workflows whose risk lives in that interaction
  keep end-to-end scenarios that walk several helpers in sequence
  (`refund_worker_lifecycle.sql`,
  `reconcile_event_purchase_for_checkout_session.sql`, the enrollment
  reconciliation tests, `tests/migrations/`). Assertions that overlap a
  helper's test are acceptable there; what is not acceptable is a caller
  re-testing a helper's branch matrix through its own fixtures.
- Before removing a scenario from a caller, confirm the equivalent scenario
  exists in the helper's test or in a workflow test: coverage moves, it is
  never dropped. Seed rows that only served a moved scenario go with it.

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
- `SEED DATA` builds prerequisite state with commented `fx_*` fixture calls
  and `insert` statements, ordered by foreign-key dependency and then by
  table name; each scenario gets its own rows rather than mutating shared
  ones.
- `TESTS` only invokes the behavior under test and asserts persisted state.
  Direct writes appear in `TESTS` only when the write itself is the behavior
  under test (constraints and triggers).
- A test asserts only values it wrote itself. Any value a scenario depends on
  (a published flag, a date, a capacity, a name that is looked up) is written
  explicitly by the test, never inherited from a fixture default.
- Rejections assert the SQLSTATE and message as described in the
  [error contract](#error-contract).
- Files never take table-level locks (`alter table`, `lock table`,
  `truncate`): the suite runs in parallel against one database, and every
  file must stay an independent `begin ... rollback` transaction.
- Each file owns its identifiers and unique key values. The UUID prefix of
  its `\set` variables is used by no other file (`just db-lint`), and no two
  files seed the same value into a unique index: usernames, emails, community
  names, provider references, idempotency keys, meeting ids
  (`just db-tests-seed-keys`, also run in CI). Two files inserting the same
  unique value block each other and can deadlock under `pg_prove -j`.

### Fixture functions

`tests/fixtures/` defines one `fx_<table>` function per baseline table:
`fx_community`, `fx_group_category`, `fx_event_category`, `fx_group`,
`fx_user`, `fx_event`, `fx_event_ticket_type`, and
`fx_event_ticket_price_window`, plus the `fx_insert_row` helper they share.

- The signature takes the row identifier and its foreign keys as positional
  parameters followed by one optional `jsonb` overrides argument:
  `fx_event(p_event_id, p_group_id, p_event_category_id, p_overrides)`.
  Override keys are column names, written alphabetized with
  `jsonb_build_object(...)`; unknown keys fail as unknown columns.
- Fixtures set only the required plumbing with placeholder values
  (`'Fixture Group'`, `'fixture-user-<uuid>'`, `'https://fixture.test/...'`)
  and never set interesting state: no published flags, dates, capacity,
  payment recipients, or meeting fields. Values that must be unique derive
  from the identifier, so files with distinct UUID prefixes never collide.
- Fixtures insert rows directly and never call domain functions. There is one
  fixture per table and no graph builders.
- Entity-under-test rows and scenario-specific rows (attendees, purchases,
  offers, team memberships, ...) stay as inline `insert` statements.
- Fixture calls without overrides are grouped under one `-- Baseline ...`
  comment in foreign-key order with no blank lines between them; a fixture
  call whose overrides encode scenario state gets its own descriptive comment.
- `just db-tests` and `just db-tests-file` install the fixtures after the
  migrations (`just db-install-tests-fixtures`); the application loader never
  loads them.

```sql
-- Baseline community, categories, group and attendee
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'attendeeID');

-- Event open for registration
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', now() + interval '1 day'
));
```

### Schema tests

`tests/schema/` asserts the catalog: tables and extensions, columns, keys,
indexes, functions and triggers, constraints and reference data. Every
migration updates the relevant file.

### Migration tests

`tests/migrations/` holds representative-data upgrade tests for migrations
that translate or destroy existing state. A migration `NNNN` has two files:
`NNNN_<name>_seed.sql`, which inserts rows in the shape of schema `NNNN - 1`
with raw `insert` statements (fixtures are not installed, and they follow the
current schema), and `NNNN_<name>.sql`, a pgTAP file asserting the upgraded
rows. `just db-migration-test NNNN` recreates the migration database, applies
the schema up to `NNNN - 1`, loads the seed, applies every remaining schema
migration and the function loader, and runs the assertions;
`just db-migration-tests` runs every pair. The upgrade always continues to the
latest schema because the function loader only resolves against it, so the
seeded rows also prove they survive later migrations.

### Rust contract tests

`ocg-server/src/db/contract_tests/` runs the ignored `db_contracts` tests
against a real database migrated and seeded with `tests/data/contract.sql`.
They guard the JSON boundary between functions and Rust DTOs, lock ordering,
and the error SQLSTATEs. One module per database trait (`auth.rs`,
`badges.rs`, `common.rs`, `community.rs`, `dashboard_*.rs`, `event.rs`,
`group.rs`, `meetings.rs`, `notifications.rs`, `payments.rs`, `site.rs`)
holds the tests for that trait's functions; `helpers.rs` holds the seeded
identifiers, connection helpers, and shared assertions. A change to a
JSON-returning function, a DTO, a wrapper, or `contract.sql` runs
`just db-contract-tests`.

### Commands

```nu
just db-lint
just db-tests
just db-tests-file database/tests/functions/<folder>/<function>.sql
just db-tests-seed-keys
just db-contract-tests
just db-migration-test 0081
just db-migration-tests
```

`just db-tests` recreates the test database, installs the fixtures, and runs
`pg_prove` with one job per CPU; CI runs the same suite with `--jobs 4`.

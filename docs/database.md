# Database layer

This document describes the architecture of the PostgreSQL layer of Open
Community Groups: how the sources are laid out, how functions reach the
database, how failures are classified, where authorization lives, how
background jobs are coordinated, and how the layer is tested. Business logic
lives in PostgreSQL functions; the Rust server calls them through thin
wrappers and consumes their results as typed DTOs.

It states rules and contracts only. Inventories of functions, helpers, and
columns, worked examples, and fixture or file-format details live in the SQL
sources, their pgTAP tests, and pull request descriptions. The document
changes only when a rule or contract described here is introduced, removed,
or altered; most changes do not touch it.

## Folder layout

```text
database/
  migrations/
    schema/       Numbered Tern migrations: tables, indexes, constraints,
                  reference data, triggers, drop statements
    functions/    Function sources loaded by 001_load_functions.sql
      internal/<concern>/   SQL-only helpers, never called from Rust
      <trait folders>/      Rust-facing functions, one folder per trait
      triggers/             Trigger functions
    migrate.sh    Applies schema migrations, then reloads every function
  scripts/
    lint.sh       Convention checks run by `just db-lint` and CI
  tests/
    schema/       pgTAP catalog tests
    functions/    pgTAP tests mirroring migrations/functions one to one
    fixtures/     fx_* fixture functions installed into the test database
                  by the test recipes, never by the application loader
    data/         Deterministic seeds for contract (contract.sql) and
                  end-to-end (e2e.sql) databases
    migrations/   Representative-data upgrade tests
```

Rust-facing function folders mirror the database traits in `ocg-server/src/db`
(and `ocg-redirector/src/db.rs` for `redirector/`): a function called from
`db/dashboard/group.rs` lives in `functions/dashboard-group/`, and so on.
`triggers/` holds every trigger function. Operator-only entry points run
through `psql` stay in the folder of the feature they serve.

Helpers that are only called from other SQL functions live under
`functions/internal/<concern>/`, grouped coarsely by the rule they own. The
path answers "is this a contract change?": a signature or result shape under
`internal/` may change freely as long as its SQL callers and tests are
updated in the same change; anything outside `internal/` is consumed by Rust
and requires the DTO, wrapper, and contract-test updates described below.
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
  users. This covers worker and queue mechanics, provider webhook consistency
  checks, `p_*_id is null` contract checks, `else` branches for unreachable
  enum values, trigger immutability guards, and SQL-only helpers whose
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

A function returns `jsonb_build_object('conflict', '<code>')` instead of
raising only for an outcome where the Rust caller has a next step (reusing a
pending purchase, queueing the user). Everywhere else, raise with the error
contract.

## Authorization rule

- Rust route middleware is the authorization boundary. The path- and
  selection-scoped permission middlewares in
  `ocg-server/src/handlers/auth/middleware.rs` run before any dashboard
  handler, and `ocg-server/src/router/tests.rs` asserts that every community
  and group dashboard mutation route rejects a read-only user.
- SQL functions enforce scope and state, not permissions: parent/child
  ownership (`event.group_id`, `group.community_id`), active/deleted/canceled
  flags, row ownership (`p_user_id`), and invariants under locks.
- `p_actor_user_id` identifies the actor for audit rows and ownership. It is
  never used to look up permissions.
- `user_has_group_permission` and `user_has_community_permission` may be
  called from SQL only to answer a domain question about a *different*
  resource than the one the route authorized (for example the new parent
  group of a group being moved) or to compute notification recipients.

### Trust model

These rules describe conventions inside one trust boundary, not enforcement
the database provides on its own:

- A database function trusts its caller to have authorized the actor. Given a
  matching `p_group_id` or `p_community_id`, a mutation acts for any
  `p_actor_user_id` it is handed; the actor is an audit identity, not proof of
  permission. Every entry point that calls these functions (today: the Rust
  server behind its route middleware, plus the operator-only functions run
  through `psql` by a database administrator) is responsible for that
  authorization. A second service, an administrative API, or a job runner
  that calls the functions directly must authorize before it calls; the route
  test covers only the routes of this server.
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
  rules together with the layout and test rules in this document.

## Job lifecycles

Background work is coordinated through database state so that workers can be
restarted safely and external calls stay outside transactions. Every durable
queue (notifications, meeting syncs, badge awards, payment jobs) follows the
same phases:

- **Claim**: a worker takes a row with `for update skip locked` and records a
  claim identity and timestamp.
- **Outcome**: the worker records success, a retryable failure, or a terminal
  failure against its claim. Stale claims are rejected so a delayed worker
  cannot overwrite a newer attempt.
- **Release** (notifications): a worker interrupted by shutdown between
  attempts returns its claim to the queue without recording an outcome; the
  row becomes claimable immediately and keeps its attempt count and last
  error, so a restart does not spend the retry budget. The same stale claim
  guard applies.
- **Stale claim recovery**: periodic functions release claims whose worker
  disappeared.
- **Operator recovery**: exhausted work can be retried or completed with
  external evidence from the dashboard, through functions that share one
  definition of "exhausted" with the views that surface it.

Idempotency keys and provider references are stored before any external side
effect, so retries and webhooks can be reconciled, and the idempotency key is
the only duplicate guard when work is enqueued. Provider-mediated payment
work is one `payment_job` row (worker mechanics) plus one typed domain row
(outcome); a job that reaches `completed` has its outcome on the domain row,
and trigger functions hold that invariant in both directions.

## Shared predicates and helpers

Each domain rule has one home under `functions/internal/<concern>/`; callers
delegate instead of repeating the predicate, so the rule cannot drift between
files. This covers lock-and-validate entry points (`lock_active_event`,
`lock_active_group`), status sets that reserve capacity, the per-user
enrollment state projection, search filter parsing, and the JSON projections
and encodings read by Rust (`epoch_seconds` for every event and enrollment
timestamp).

Extract by meaning, not by size or repetition alone. A predicate, status set,
or projection gets a named helper when it encodes a domain rule with more
than one home; a short sequence with a single caller stays inline when
reading it in place needs less context than following a call. When a change
touches the second occurrence of such a rule, extract it and delegate from
the occurrences the change already reads; sweeping every other occurrence is
a follow-up, not a requirement of the change. The test of a good extraction
is that a contributor can understand and safely change the workflow with
less context, not that the caller became shorter.

## Prior state, row types and phases

- **Write paths read prior state from rows.** A mutation locks the rows it
  changes (`select e.* into v_event from event e ... for update of e`) and
  passes `%rowtype` values to its helpers. Public JSON projections are read
  models for Rust and are never used as the prior state of a write. A
  Rust-facing function that needs prior state takes identifiers and reads
  the row itself. Association rows read as prior state must still be
  unchanged when the comparison runs, so comparisons happen before the
  statements that replace those rows.
- **Payload timestamps are compared at whole seconds.** Helpers that compare
  a stored timestamp with one parsed from a payload truncate the stored value
  with `date_trunc('second', ...)`, the precision `epoch_seconds` gives the
  dashboard, so a round-tripped value never reads as a change. JSON
  collections that carry timestamps are never compared as raw `jsonb`
  (PostgreSQL and chrono spell the same instant differently); both sides go
  through a comparison-only projection that re-encodes timestamps as
  `epoch_seconds` before structural equality. A sub-second-only change is
  therefore written without being detected as a change; this is accepted.
- **Composites use `returns table`.** No named composite types exist; a
  helper returning several values declares `returns table (...)` and callers
  `select * into v_record` and copy composite columns into `%rowtype` locals.
- **Large mutations are split on phase boundaries.** An orchestrator keeps
  the lock order and the decisions; a phase (validate, protect, mutate,
  confirm, audit, return) moves to an `internal/` helper that takes the
  locked rows when it is a unit a reader wants to name and reason about on
  its own, or when another flow needs the same transition, not merely because
  it is long. Phases with one caller and a few statements stay inline.

### Test ownership when extracting helpers

- Every helper has its own test under `tests/functions/internal/<concern>/`
  covering its full branch matrix. Callers do not repeat that matrix.
- A caller's test keeps every scenario that proves the caller's own decisions
  (state transitions, audit rows, returned payload, label mapping) and at
  least one wiring scenario per delegated rejection, proving the helper is
  called and its error propagates.
- Helpers can each be correct while their ordering, inputs, or combined state
  transitions are wrong, so workflows whose risk lives in that interaction
  keep end-to-end scenarios that walk several helpers in sequence. What is
  not acceptable is a caller re-testing a helper's branch matrix through its
  own fixtures.
- Before removing a scenario from a caller, confirm the equivalent scenario
  exists in the helper's test or in a workflow test: coverage moves, it is
  never dropped.

## Inline SQL in Rust

Trivial single-table reads and writes may stay inline in `ocg-server/src/db`.
Anything with a join, a branch, or a domain rule (a status filter, a
soft-delete flag, ownership) lives in a function with a mirrored pgTAP test.

## Tests

### pgTAP function tests

- Every function file has a test at the same path under `tests/functions/`;
  changing a function updates its test in the same change.
- Each file is an independent `begin; ... rollback;` transaction with an
  exact `plan` count. The suite runs in parallel against one database, so
  files never take table-level locks (`alter table`, `lock table`,
  `truncate`).
- Each file owns its identifiers and unique key values: the UUID prefix of
  its variables is used by no other file (`just db-lint`), and no two files
  seed the same value into a unique index (`just db-tests-seed-keys`, also
  run in CI). Two files inserting the same unique value block each other and
  can deadlock under `pg_prove -j`.
- A test asserts only values it wrote itself; any value a scenario depends
  on is written explicitly by the test, never inherited from a fixture
  default. Each scenario gets its own rows rather than mutating shared ones.
- Tests invoke the behavior under test and assert persisted state. Direct
  writes are the behavior under test only for constraints and triggers.
- Rejections assert the SQLSTATE and message as described in the
  [error contract](#error-contract).

Existing test files are the reference for file layout and naming.

### Fixture functions

`tests/fixtures/` defines one `fx_<table>` function per baseline table. A
fixture takes the row identifier and its foreign keys as positional
parameters followed by one optional `jsonb` overrides argument whose keys are
column names. Fixtures set only the required plumbing with placeholder
values and never set interesting state (no published flags, dates, capacity,
payment recipients, or meeting fields); unique values derive from the
identifier, so files with distinct UUID prefixes never collide. Fixtures
insert rows directly and never call domain functions; there is one fixture
per table and no graph builders. Entity-under-test rows and scenario-specific
rows stay as inline `insert` statements. The test recipes install the
fixtures after the migrations; the application loader never loads them.

### Schema tests

`tests/schema/` asserts the catalog: tables and extensions, columns, keys,
indexes, functions and triggers, constraints and reference data. Every
migration updates the relevant file.

### Migration tests

`tests/migrations/` holds representative-data upgrade tests for migrations
that translate or destroy existing state. A migration `NNNN` has a seed file
that inserts rows in the shape of schema `NNNN - 1` with raw `insert`
statements and a pgTAP file asserting the upgraded rows.
`just db-migration-test NNNN` applies the schema up to `NNNN - 1`, loads the
seed, applies every remaining migration and the function loader, and runs the
assertions, so the seeded rows also prove they survive later migrations.

### Rust contract tests

`ocg-server/src/db/contract_tests/` runs the ignored `db_contracts` tests
against a real database migrated and seeded with `tests/data/contract.sql`.
They guard the JSON boundary between functions and Rust DTOs, lock ordering,
and the error SQLSTATEs, with one module per database trait. A change to a
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

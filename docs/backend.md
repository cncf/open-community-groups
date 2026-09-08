# Backend layer

This document describes how the `ocg-server` backend is organized and the
conventions every change to it follows: which module may depend on which,
where a type lives, how side effects are made durable, how errors reach
users, which layer proves which behavior, and how work that leaves the
process is bounded. It complements [database.md](database.md), which owns the
PostgreSQL side of the `db` boundary.

The document describes the current rules only. When a change introduces or
adjusts a cross-cutting backend pattern, the matching section is updated in
the same change. Sections whose pattern is still being introduced say so
explicitly and are completed by the change that lands the pattern.

## Layer map

```text
ocg-server/src/
  router/      Route tables, permission middleware layering, shared State
  handlers/    HTTP handlers: extraction, delegation, response shaping
  services/    Workflows, managers, providers, workers, notifications
  db/          Database traits, PostgreSQL wrappers, operation types, mock
  types/       Domain shapes, read models, request forms
  templates/   Askama Template structs, view-only enums, filters, emails
```

Dependencies point in one direction: `router -> handlers -> services -> db`.
`types/` and `templates/` are leaves.

Allowed edges:

- `templates -> types`, `db -> types`, `services -> types`.
- `services -> templates::notifications` for the email templates only, whose
  serialized form is the `template_data` contract described in
  [Serde derives](#serde-derives).
- `handlers -> db` for reads through `DynDB`: page, details, list, and lookup
  handlers keep their direct reads.

Forbidden edges:

- `types -> {templates, services, db, handlers}`.
- `templates -> {services, db, handlers}`.
- `db -> {templates, services, handlers}`.
- `services -> handlers`.
- `handlers -> db::<module>::{*Input, *Result}` operation types. A handler
  that needs to build one is orchestrating a workflow and delegates it to
  `services/`.

The interim check is `rg 'templates::|services::' ocg-server/src/db
ocg-server/src/types` returning nothing for the migrated files; edges that
still exist are being removed file by file and are not a precedent for new
code.

## Type ownership and placement

A type lives where the contract it represents is consumed. A serde derive is
a symptom of a boundary, not the rule for where a type goes.

- `types/`: domain shapes, read models returned by SQL functions, and every
  request form or DTO that a service or manager consumes. A form type that a
  handler validates and then hands to a manager is a service contract and
  moves to `types/` together with the manager.
- `templates/`: `#[derive(Template)]` structs, view-only enums (`Content`,
  `Tab`), `filters.rs`, `helpers.rs`, and `notifications.rs` email templates.
  Rendering helpers (`format_payment_amount`, `is_paid_attendee`, and
  similar) stay next to the template that uses them unless a handler or
  service also calls them.
- `db/<module>.rs`: input and result types for that module's own SQL
  operations, consumed only by `db` and `services`.
- `handlers/`: only response-only shapes that no other layer reads
  (`EventAvailability`, HTMX trigger payloads).

Placement inside `types/`:

- A type shared by two or more dashboard sections, or by the public site,
  lives in a domain module (`types/event.rs`, `types/group.rs`).
- A type used by exactly one dashboard section lives in
  `types/dashboard/<scope>/<section>.rs`, mirroring
  `handlers/dashboard/<scope>/<section>.rs`.
- A type is promoted to a domain module when its second consumer appears,
  not before.

## Naming

- The same name in different modules is allowed only for different
  projections of one concept for different audiences (for example the group
  and user views of a CFS submission). Identical structs are never
  duplicated; the second occurrence imports the first.
- Different kinds of shape use suffixes: `*Input` and `*Update` for
  validated forms, `*Filters` for list filters, `*Output` for paginated
  results, `*Summary` and `*Full` for read-model projections, `*Stats` for
  aggregates.
- A read model and the form that mutates it never share a name in the same
  crate (`Event` is the read model, `EventInput` the form).

## Serde derives

`Serialize` and `Deserialize` appear only where a type crosses a boundary:

- SQL JSON returned by or passed to a database function.
- Query strings (`serde_qs`) and form bodies.
- Notification `template_data`.

Template structs that are only rendered do not derive them.

Persisted notification payloads are a compatibility contract.
`templates::notifications::*` structs are stored as `template_data` and read
back by `DeliveryWorker::prepare_content` after deployment. Moving or
renaming one of these types must not change its serialized form. Removing a
field, changing a field's meaning, or evolving an enum requires an explicit
decision recorded in the PR and, when incompatible, a conversion step in
`prepare_content`. Fixtures for supported older shapes live in
`services/notifications/tests.rs` as literal JSON, never built from the
current constructors, so a breaking change fails a test instead of silently
updating both sides.

## Managers

A manager is a trait with a `mockall` mock (`#[cfg_attr(test, automock)]`)
and a `Dyn*` alias in `router::State`. It exists for a cohesive workflow
family that benefits from a mockable boundary between handlers and the
database. Opening a transaction, calling an external provider, or performing
two or more database writes are signals that a workflow belongs behind a
manager, not the rule; workflow cohesion and the value of the test boundary
decide the scope.

Current managers and provider traits:

- `services::notifications::NotificationsManager` (`PgNotificationsManager`)
  with the `EmailSender` provider trait.
- `services::payments::PaymentsManager` (`PgPaymentsManager`) with the
  `PaymentsProvider` trait and the webhook reconciler, refund recorder, and
  notification composer around it.
- `services::meetings::MeetingsProvider`, keyed by provider in
  `DynMeetingsProviders`.
- `services::images::ImageStorage`.

Everything that does not warrant a manager is a free function over
`&dyn DBOperations` in `services/`, or stays in the handler when it is
request shaping only.

Manager wiring follows `setup_payments_manager` in `main.rs`; handler tests
inject mocks through `TestRouterBuilder::with_*_manager`, whose defaults
expect no calls.

This section is completed with a worked example when the first domain
manager extracted from the handlers lands.

## Side-effect durability

Every side effect chooses its durability at the call site.

- **Required** work is part of the operation: it runs inside the caller's
  `DBExt::transaction(|tx| ...)` closure and its failure propagates, rolling
  the operation back. Required notifications call the named
  `services::notifications::enqueue::*` functions with the transaction
  handle. The transactional guarantee comes from the closure and is proven by
  rollback tests, not by a parameter type: `DBUnitOfWork` implements
  `DBOperations`, so `tx: &dyn DBOperations` cannot enforce it.
- **Best-effort** work runs after commit, is logged with `warn!` on failure
  together with the identifiers needed to reconstruct it, and never undoes or
  fails the core operation. Best-effort notifications build their payload
  and call `NotificationsManager::enqueue`.

Enqueue helpers own the notification content; callers pass identifiers and
configuration. Content assertions live with the helper, not with the caller.

## Error contract

`handlers/error.rs` owns `HandlerError`. `database.md` describes the SQL side:
user-facing rejections raise `OCG01`, everything else stays internal.

| Variant | Status | Body |
| --- | --- | --- |
| `Auth(_)` | 401 | empty |
| `Database(msg)` | 422 | `msg`, the `OCG01` message raised by SQL |
| `Deserialization(msg)` | 422 | `msg` |
| `Forbidden` | 403 | empty |
| `NotFound` | 404 | empty |
| `Validation(report)` | 422 | the `garde` report |
| `Other`, `Serde`, `Session`, `Template` | 500 | empty |

Rules:

- `From<anyhow::Error>` is the classification point. It inspects the
  SQLSTATE and maps `OCG01` to `Database(msg)`; any other database error and
  every non-database error become `Other`. Handlers propagate `anyhow`
  results with `?` and never match on message text.
- A typed service error with an `Other(anyhow::Error)` variant converts to
  `HandlerError` through `HandlerError::from(err)`, never by wrapping in
  `HandlerError::Other(err)` directly. Wrapping directly turns an `OCG01`
  rejection raised inside the service into a 500.
- `Database` is meant for `OCG01` messages. Application-side rejections in
  handlers that still construct it are being migrated to a dedicated
  variant; do not add new sites.
- Internal detail (database errors, provider errors, panics) is logged
  through the handler span and never written to the response body.

## Handler shape

A handler does extraction, delegation, and response shaping, in this order:

1. **Extraction**: path, query, and form data through the typed extractors
   in `handlers/extractors.rs`: `CurrentUser`, `CommunityId`,
   `SelectedCommunityId`, `SelectedGroupId`, `ValidatedForm<T>`,
   `ValidatedFormQs<T>`, `OAuth2`, `Oidc`. Extractors deserialize and run
   `garde` validation; a handler does not re-validate.
2. **Authorization**: route-level permission middleware in
   `router/dashboard.rs` is the authorization boundary (see the
   authorization rule in `database.md`). A handler only adds checks the
   route cannot express, such as ownership of a specific row.
3. **Reads**: page, details, list, and lookup handlers read through `DynDB`
   directly.
4. **Action**: one call to a manager or a `services/` function. A handler
   never opens a transaction, calls a provider, or builds `db/` operation
   types.
5. **Side effects**: best-effort work after the action, following
   [Side-effect durability](#side-effect-durability).
6. **Response**: status, headers (`HX-Trigger`, `HX-Redirect`,
   `hx-push-url`), and body. Response-only shapes live in the handler.

Every `Result`-returning handler carries `#[instrument(skip_all, err)]`.
Extractors keep `#[instrument(skip_all, err(Debug))]` because their rejection
type is a tuple.

Pure domain logic (recurrence expansion, eligibility predicates) lives in
`services/` or `types/`, not under `handlers/`.

Known gaps: several mutation handlers (`handlers/dashboard/group/events.rs`,
`handlers/event.rs`, `handlers/dashboard/group/attendees.rs`, and others)
still open transactions and build `db/` operation types themselves;
`handlers/dashboard/group/events/recurrence.rs` holds domain logic; a few
handlers use `skip(db)` or `err(Debug)`. These are being migrated; new
handlers follow the shape above.

## Test layering

Each behavior is proven at the cheapest layer able to prove it.

- **Handler tests** (`handlers/**/tests.rs`) build the router with
  `TestRouterBuilder`, mock managers and `MockDB`, and assert status,
  headers, and body. Session and permission setup uses the shared helpers
  (`expect_authenticated_session`, `expect_authenticated_community_session`,
  `expect_authenticated_group_session`, `expect_community_permission`,
  `expect_group_permission`); transactions use
  `expect_successful_transaction` and `expect_rolled_back_transaction`.
- **Manager and service tests** (`services/**/tests.rs`) mock `MockDB` and
  the provider traits and assert workflow order, commit or rollback, and
  which side effects were enqueued.
- **Notification content** is asserted in the enqueue helper tests
  (the `tests` module of `services/notifications/enqueue.rs`), not in the
  tests of the callers.
- **Real JSON contracts** between SQL functions and Rust DTOs are asserted in
  `db/contract_tests` against a real database (`just db-contract-tests`).
- **Real-database lifecycle behavior** that mocks cannot prove (rollback on
  drop, commit failure) also lives under `db/contract_tests`.

A handler test is removed only when the PR names the test at the new layer
that proves the same behavior: same failing call, same rollback or
suppressed side effect, same status. Test counts are reported for
information and never decide.

This section is refined with the mock surface per layer when the first
domain manager extracted from the handlers lands.

## Bounded operations and worker health

Rule for new code: every call that leaves the process has a connection
deadline and a total-operation deadline set at the boundary that owns the
client, and a timed-out write is classified by whether the external outcome
is known (a call with a deterministic idempotency key is retryable; one
without follows the unknown-outcome path such as
`mark_notification_delivery_unknown` or payment reconciliation, never a blind
retry). New outbound clients follow the Zoom client
(`services/meetings/zoom/client.rs`), which is built once with an explicit
`timeout`.

Current behavior and known gaps:

- The Stripe client (`services/payments/provider/stripe.rs`) and the GitHub
  profile and email loaders (`src/auth.rs`) use `reqwest::Client::new()`,
  which has no connection or request timeout. A provider that accepts the
  connection and never answers holds the calling task indefinitely.
- Workers are built on `services/workers.rs`: `run_worker` drives
  cancellation-aware iterations, `claim_loop` claims and releases jobs, and
  `BackgroundTasks` tracks spawned workers and waits for all of them on
  shutdown. A worker finishes its in-flight operation before stopping, so a
  stalled provider call blocks shutdown for as long as it stalls.
- `BackgroundTasks::spawn` discards the `JoinHandle`, and
  `router::health_check` returns `200` unconditionally. A worker that panics
  or returns early is not observed and does not change the health response.
- Password verification runs in `tokio::task::spawn_blocking`;
  `password_auth::generate_hash` on sign-up and password update runs on the
  async executor, and neither path has a concurrency bound.
- The activity tracker is best-effort: `track` awaits capacity on a bounded
  channel, the flusher logs failed writes and drops the affected counters,
  and aggregation keys are not capped.

Deadlines, worker exit observation, readiness semantics, and blocking-work
bounds are documented here as they land, together with the configuration
that controls them.

## Transactional reads and cache ownership

Rule: process caches hold committed data only. A read inside a
`PgUnitOfWork` must not be served from a shared cache, because the cached
value may predate the transaction's own writes, and must not populate it,
because uncommitted data must not become visible to other requests.

Current behavior: the `#[cached]` reads (`get_site_settings`, community
lookups, dashboard statistics) sit on blanket `impl<T: PgExecutor>` blocks,
so `PgDB` and `PgUnitOfWork` share the same cache entries. Inside a
transaction, a cache hit can return a value older than the transaction
snapshot, and a cache miss caches the transaction's uncommitted view for the
TTL. Until the bypass exists, code that reads a cached value after writing
it inside the same transaction must not rely on seeing its own write, and a
new `#[cached]` read is added only for data that transactions never mutate
before reading. Acceptable staleness is the cache TTL; invalidation is
unchanged. The bypass mechanism and its tests are documented here when they
land.

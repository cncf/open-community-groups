# Backend layer

This document describes the architecture of the `ocg-server` backend: which
module may depend on which, where a kind of type lives, how side effects are
made durable, how errors reach users, which layer proves which behavior, and
how work that leaves the process is bounded. It complements
[database.md](database.md), which owns the PostgreSQL side of the `db`
boundary.

It states rules and contracts only. Inventories of functions, types, and
configuration keys, worked examples, tuning constants, measurements, and
rejected alternatives live in code doc comments, tests, and pull request
descriptions. The document changes only when a rule or contract described
here is introduced, removed, or altered; most changes do not touch it.

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

`layers::layer_dependencies_follow_backend_rules` (`ocg-server/src/layers.rs`,
run by `just server-tests`) enforces these rules over every Rust file under
the layered directories, tests included. Its allowance lists are empty and an
allowance that matches nothing fails the test, so new code never adds one.

A type that two layers need lives in `types/`. A `db` operation type that
carries notification content stores it as an already serialized
`serde_json::Value`, so `db` never depends on the email template types.

## Type ownership and placement

A type lives where the contract it represents is consumed. A serde derive is
a symptom of a boundary, not the rule for where a type goes.

- `types/`: domain shapes, read models returned by SQL functions, and every
  request form or DTO that a service or manager consumes. A form type that a
  handler validates and then hands to a manager is a service contract and
  belongs here.
- `templates/`: `#[derive(Template)]` structs, view-only enums, filters,
  helpers, and email templates. Rendering helpers stay next to the template
  that uses them unless a handler or service also calls them. View models
  prepared for rendering and payloads that only the handler deserializes and
  the template consumes stay with the template.
- `db/<module>.rs`: input and result types for that module's own SQL
  operations, consumed only by `db` and `services`.
- `handlers/`: only response-only shapes that no other layer reads and
  request-shaping inputs that the handler consumes itself.
- Manager input and outcome types live in the manager module that consumes
  them, next to the trait. The validated forms they wrap live in `types/`.

Placement inside `types/`:

- A type shared by two or more dashboard sections, or by the public site,
  lives in a domain module (`types/event.rs`, `types/group.rs`).
- A type used by exactly one dashboard section lives in
  `types/dashboard/<scope>/<section>.rs`, mirroring
  `handlers/dashboard/<scope>/<section>.rs`.
- A type is promoted to a domain module when its second consumer appears,
  not before.
- Dashboard list defaults live in `types/dashboard.rs` next to the
  `*Filters` that use them.
- Two projections of one concept for different audiences stay separate types
  until a consumer handles both uniformly; a generic shape without a reader
  couples them for nothing.

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
- Template data embedded in a page through the `json` filter.

Template structs that are only rendered do not derive them.

Persisted notification payloads are a compatibility contract.
`templates::notifications::*` structs are stored as `template_data` and read
back by the delivery worker after deployment. Each implements
`templates::notifications::NotificationTemplate`, which owns the email
subject and the completion of stored root-relative URLs with the deployment
base URL; the worker only maps a `NotificationKind` to its struct and renders
it through that trait. Moving or renaming one of these types must not change
its serialized form. Removing a field, changing a field's meaning, or
evolving an enum requires an explicit decision recorded in the PR and, when
incompatible, a conversion step in the worker. Fixtures for supported older
shapes live in `services/notifications/tests.rs` as literal JSON, never
built from the current constructors, so a breaking change fails a test
instead of silently updating both sides.

## Managers

A manager is a trait with a `mockall` mock (`#[cfg_attr(test, automock)]`)
and a `Dyn*` alias held in `router::State`. It exists for a cohesive workflow
family that benefits from a mockable boundary between handlers and the
database. Opening a transaction, calling an external provider, or performing
two or more database writes are signals that a workflow belongs behind a
manager, not the rule; workflow cohesion and the value of the test boundary
decide the scope. The current managers are the `*Manager` traits under
`services/`, with providers (`PaymentsProvider`, `MeetingsProvider`,
`EmailSender`, `ImageStorage`) as the traits they call out through.

Everything that does not warrant a manager is a free function over
`&dyn DBOperations` in `services/`, or stays in the handler when it is
request shaping only.

Manager methods return a typed error with exactly two variants,
`Rejected(String)` and `Other(anyhow::Error)`. `Rejected` is a business
decision made in Rust; `Other` wraps database and provider failures unchanged
so `HandlerError::from(anyhow::Error)` can still classify `OCG01` rejections.
Provider errors with their own user-facing variants convert into the manager
error with `From`, mapping correctable variants to `Rejected`. Conflict
outcomes are returned as the kebab-case `Display` of the `db` conflict enums,
so handlers never import a `db` type.

Pure eligibility predicates take the clock as a parameter: the manager reads
`Utc::now()` once per operation and passes it down; `Utc::now()` convenience
wrappers exist only for templates and delegate to the `*_at(now)` variants.

Manager wiring follows `setup_payments_manager` in `main.rs`; handler tests
inject mocks through `TestRouterBuilder::with_*_manager`, whose defaults
expect no calls.

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
  fails the core operation. Best-effort notifications go through the named
  helpers in `services::notifications::best_effort`, each of which loads its
  context, builds its payload, enqueues, and logs, so the caller passes
  identifiers only.

Enqueue helpers own the notification content; callers pass identifiers and
configuration. Content assertions live with the helper, not with the caller.
Pure payload builders live in `services::notifications::payloads`. No handler
constructs a `db`-owned notification type.

Durability has a limit that no code can remove: when the commit
acknowledgement is lost (a connection dropped after `commit` was sent), the
outcome is uncertain to the caller. Only the persisted state is authoritative;
callers surface the error and never assume the write failed.

## Error contract

`handlers/error.rs` owns `HandlerError`. `database.md` describes the SQL side:
user-facing rejections raise `OCG01`, everything else stays internal.

| Variant | Status | Body |
| --- | --- | --- |
| `Auth` | 401 | empty |
| `Database(msg)` | 422 | `msg`, the `OCG01` message raised by SQL |
| `Deserialization(detail)` | 422 | `invalid request payload`; detail logged |
| `Forbidden` | 403 | empty |
| `NotFound` | 404 | empty |
| `Rejected(msg)` | 422 | `msg`, a business rejection decided in Rust |
| `Validation(report)` | 422 | the `garde` report |
| `Other`, `Serde`, `Session`, `Template` | 500 | empty |

Rules:

- `From<anyhow::Error>` is the classification point. It inspects the
  SQLSTATE and maps `OCG01` to `Database(msg)`; any other database error and
  every non-database error become `Other`. Handlers propagate `anyhow`
  results with `?` and never match on message text.
- `Database` is constructed only by `From<anyhow::Error>`. A rejection decided
  in Rust (a missing prerequisite, an invalid state transition, a form rule
  that `garde` cannot express) is `Rejected(msg)` with a concise, lowercase,
  user-facing message. Wrapping such a rejection in `anyhow!` turns it into a
  500.
- A typed service error with an `Other(anyhow::Error)` variant converts to
  `HandlerError` through `HandlerError::from(err)`, never by wrapping in
  `HandlerError::Other(err)` directly, which would turn an `OCG01` rejection
  raised inside the service into a 500. Its user-facing variants map to
  `Rejected`.
- `Deserialization` carries parser output that is never returned to the
  client; `into_response` logs it and answers with the fixed body. Parse
  failures in the validated extractors and query-string conversions use this
  variant; `garde` failures keep returning the field-level report through
  `Validation`.
- `Auth` carries no payload. Callers that need the underlying cause in logs
  record it before mapping.
- Internal detail (database errors, provider errors, panics) is logged
  through the handler span and never written to the response body.

## Handler shape

A handler does extraction, delegation, and response shaping, in this order:

1. **Extraction**: path, query, and form data through the typed extractors
   in `handlers/extractors.rs`. Extractors deserialize and run `garde`
   validation; a handler does not re-validate. A handler that reads the
   query string for its own use takes `ValidatedQuery<T>`; `RawQuery` remains
   only where the raw string is forwarded to a shared `prepare_*` helper
   because the filter type is known at runtime, and that helper parses it
   with `ValidatedQuery::<T>::parse` so the contract has one implementation.
2. **Authorization**: route-level permission middleware in
   `router/dashboard.rs` is the authorization boundary (see the
   authorization rule in `database.md`). The selected-context middleware in
   `handlers/auth/middleware.rs` resolves the community and group selected in
   the session, repairs a selection the user can no longer read, and rejects
   requests rendered for another context. A handler only adds checks the
   route cannot express, such as ownership of a specific row.
3. **Reads**: page, details, list, and lookup handlers read through `DynDB`
   directly.
4. **Action**: one call to a manager or a `services/` function. A handler
   never calls a provider or builds `db/` operation types. A handler opens a
   transaction directly only for a single write with no side effects; every
   multi-step workflow is behind a manager.
5. **Side effects**: best-effort work after the action, following
   [Side-effect durability](#side-effect-durability).
6. **Response**: status, headers (`HX-Trigger`, `HX-Redirect`,
   `hx-push-url`), and body. Response-only shapes and contracts stay in the
   handler.

Every `Result`-returning handler carries `#[instrument(skip_all, err)]`.
Extractors keep `#[instrument(skip_all, err(Debug))]` because their rejection
type is a tuple.

`db/` methods carry `#[instrument(skip(self, ...), err)]`. Because `err`
writes every span field on failure, including the `OCG01` rejections that end
as a 422, span fields are limited to stable identifiers (UUIDs, provider
object ids, enums, amounts). Payloads (JSON, attachments, template data),
free text (notes, details, reasons), binary data, bulk vectors, and `input`
structs are skipped; a `fields(entries = data.len())` keeps a size signal
when the skipped argument is a batch.

Pure domain logic (recurrence expansion, eligibility predicates) lives in
`services/` or `types/`, not under `handlers/`.

## Test layering

Each behavior is proven at the cheapest layer able to prove it. The mock
surface per layer:

- Handler (`handlers/**/tests.rs`): mocks managers and `MockDB` for reads
  and session; asserts status, headers, body, and the identifiers passed to
  the manager or notifier.
- Manager and service (`services/**/tests.rs`): mocks `MockDB`, providers,
  and `MockNotificationsManager`; asserts workflow order, commit or
  rollback, and side effects enqueued or suppressed. Manager tests do not
  import `handlers`.
- Notification helper (`enqueue`, `best_effort`, and `payloads` tests):
  mocks `MockDB` and `MockNotificationsManager`; asserts notification kind,
  recipients, `template_data` content, and the tracking record. Callers,
  including handler tests, assert only kind, recipients, and identifiers.
- Error contract (`handlers/error/tests.rs`): no mocks; asserts each
  `HandlerError` variant's status and body.
- Contract (`db/contract_tests`, `just db-contract-tests`): real database;
  asserts SQL JSON to Rust DTO shapes, the `PgUnitOfWork` lifecycle
  (rollback on drop, explicit rollback, failing deferred constraint on
  commit), and manager compositions that mocks cannot prove.

Rules that follow from the layering:

- Handler tests build the router with `TestRouterBuilder` and the shared
  session and permission helpers. A handler behind a manager has one or two
  manager expectations per test and no workflow `MockDB` expectations. Every
  typed manager error is proven at the handler with three tests: an `OCG01`
  rejection returns 422 with its message, a `Rejected` returns 422 with its
  message, and an internal failure returns 500 with an empty body.
- Handler DB-failure tests exist only when they prove something the error
  contract tests cannot: a failure mapped to a non-500 status, a suppressed
  later side effect (asserted with `.never()` on the side effect and its
  context reads), or an error path outside `HandlerError` (middleware,
  extractors). A handler that only propagates a direct `DynDB` call with `?`
  has no per-route DB-error test.
- Shared sample builders for domain types live in `types/tests.rs`;
  `handlers/tests.rs` re-exports them, and `services` or `templates` tests
  import them from `types::tests`, so test code follows the same dependency
  direction as production code.
- A test is removed only when the PR description names the test that proves
  the same behavior at another layer. A test with no replacement stays.

## Bounded operations and worker health

Rule: every call that leaves the process has a connection deadline and a
total-operation deadline set at the boundary that owns the client, and a
timed-out write is classified by whether the external outcome is known: a
call with a deterministic idempotency key is retryable; one without follows
an unknown-outcome path (recorded as unknown, or made safe to retry by the
provider adapter itself), never a blind retry.

### Outbound deadlines

Deadlines come from typed configuration under the section that owns the
client. Every HTTP client is built once through `util::build_http_client`
from an `HttpClientConfig`, whose request deadline covers the whole exchange
including the response body. SMTP has separate connect and send deadlines
applied by the email sender. PostgreSQL connections get the pool `create`,
`wait`, and `recycle` timeouts plus server-enforced `statement_timeout` and
`idle_in_transaction_session_timeout` session defaults set in
`db::pool::config_with_defaults`; a path that legitimately needs longer
raises the limit with `set local statement_timeout` inside its own
transaction.

Classification at the boundary:

- Payment provider writes carry a deterministic idempotency key and are
  retryable; durable payment jobs release their claim on failure and are
  claimed again.
- An SMTP delivery that times out after the session is established is an
  unknown outcome and is recorded as such, never retried blindly; a
  connection timeout before that point is retryable.
- A meeting provider creation without an idempotency key is made safe to
  retry by the provider adapter, which stamps every meeting with a reference
  and adopts an existing match before creating.
- A PostgreSQL statement timeout is not an unknown outcome: the server
  aborts the statement, so the write did not happen. The only ambiguous case
  is a commit whose acknowledgement is lost, which the durable job claims and
  stale-claim recovery cover.

### Workers and shutdown

Workers are built on `services/workers.rs`: `run_worker` drives
cancellation-aware iterations, `claim_loop` claims and releases jobs, and
`BackgroundTasks` spawns and observes workers.

- `BackgroundTasks::spawn` takes a worker name; several instances may share
  one. A tracked monitor records how each worker ended in the shared
  `WorkerRegistry`: a return after cancellation or an abort during shutdown
  is an expected stop, anything else is an unexpected exit logged with the
  worker name. Workers are not restarted automatically; a dead worker stays
  dead until the process restarts, and the error log line is the alert.
- Worker state is deliberately kept out of the health probe. `/health-check`
  answers whether the process can serve requests, which background workers do
  not affect; tying a probe to worker exits would remove serving capacity
  without healing anything. Worker state is reported through the periodic
  health log instead.
- `BackgroundTasks::shutdown` cancels every worker and waits up to
  `server.shutdown_grace_period_secs` for them to finish their in-flight
  unit; workers still running when the grace period expires are aborted. A
  job left in `processing` by an aborted worker is recovered by the
  stale-claim recovery workers on the next start. Idle workers stop as soon
  as they observe cancellation, and pauses between retries are
  cancellation-aware, releasing the claim instead of recording an outcome.

### Signals and identifiers

Operational signals go through tracing, the only telemetry path the server
has. The `queue-health` worker (`services/workers/queue_health.rs`)
periodically logs, per durable job queue, the pending and processing counts
and the age of the oldest pending job, and, per worker name, the running
instances and unexpected exits. Workers that scan domain rows for due work
rather than a job table have no backlog signal.

Stable identifiers make a failure reconstructible across spans: every request
gets an `x-request-id` (generated when the client sends none, echoed in the
response) that is a field of the request span, and durable jobs log their
row identifier on every outcome, from enqueue to delivery.

### CPU-heavy work

CPU-bound work runs off the async executor through
`services::blocking::BlockingExecutor`, which wraps `spawn_blocking` in a
semaphore sized by `server.max_blocking_concurrency`, so a burst cannot
saturate the blocking pool. One executor is created in `router::setup` and
shared by everything that hashes or verifies passwords.

### Bounded exports

An export that loads its rows and builds the file in memory states its
supported size explicitly and rejects larger requests with
`HandlerError::Rejected` rather than streaming. The bound is chosen from a
measurement at that size, recorded on the constant that defines it; streaming
is adopted only when the measured cost is unacceptable.

### Lossy best-effort pipelines

A best-effort pipeline states whether it is lossy or durable and what
saturation does to its callers. The activity tracker
(`src/activity_tracker.rs`) is **deliberately lossy**: page-view analytics
never delay or fail a request. Every stage hands work on with a non-blocking
send on a bounded queue, drops and counts what does not fit, and reports the
drops through tracing; a slow database delays writes instead of stalling the
request path. On shutdown the aggregator drains what is queued and hands the
final batch to the flusher; if the flusher is congested, the worker is
aborted at the end of the grace period like any other stalled worker.

## Cached reads and transactions

Rule: a `#[cached]` read caches data that is long-lived and that no
transaction mutates before reading back. The cache is a performance tool for
reference data, not a consistency mechanism.

The `#[cached]` reads sit on blanket `impl<T: PgExecutor>` blocks, so `PgDB`
and `PgUnitOfWork` share the same cache entries and there is no transactional
bypass. A cached read inside a transaction is served from the cache like any
other call, and a miss populates the cache from the transaction's view.

Consequences:

- Code that reads a cached value after writing it inside the same
  transaction must not rely on seeing its own write.
- A new `#[cached]` read is added only for data that transactions never
  mutate before reading. If such a path is needed, read the row directly
  with an uncached query rather than adding a bypass to the cached method.
- Acceptable staleness is the cache TTL; invalidation is unchanged.

Cache entries are keyed by the data they describe and are global to the
process. Every `PgDB` in a process shares them, which is the intended
production shape (one pool, one database).

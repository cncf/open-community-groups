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

The test `layers::layer_dependencies_follow_backend_rules`
(`ocg-server/src/layers.rs`, run by `just server-tests`) enforces these
rules. It reads every Rust file under the layered directories, including
tests, flattens the `crate::` paths each file references, and fails on a
forbidden edge. `LAYER_EDGE_ALLOWANCES` and
`HANDLER_OPERATION_TYPE_ALLOWANCES` are both empty: no file crosses a layer
edge in the wrong direction and no handler builds a `db` operation type. An
allowance that no longer matches any edge also fails the test, so the lists
can only stay empty; new code never adds one.

Types that lower layers need from a higher one live in `types/` instead:
meeting, image, and notification shapes (`types/{meetings,images,
notifications}.rs`) are shared by `services` and `db`; the `OCG01` SQLSTATE
constant is `db::USER_FACING_DB_ERROR_CODE`; the authentication-provider
session key is `auth::AUTH_PROVIDER_KEY`. A `db` operation type that carries
notification content stores it as an already serialized `serde_json::Value`
(`db::auth::EmailVerificationNotification::template_data`), so `db` never
depends on the email template types.

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
  service also calls them. View models prepared for rendering
  (`AuditLogEntry`, the event preview `Event`) and payloads that only the
  handler deserializes and the template consumes (the event preview `Input`
  and `Context`) stay with the template: no service or `db` operation reads
  them.
- `db/<module>.rs`: input and result types for that module's own SQL
  operations, consumed only by `db` and `services`.
- `handlers/`: only response-only shapes that no other layer reads
  (`EventAvailability`, HTMX trigger payloads) and request-shaping inputs that
  the handler consumes itself (`EventActionQuery`, `TaxRatesQuery`).
- Manager input and outcome types (`AttendEventInput`, `AttendOutcome`,
  `EventActionInput`, `PaymentJobRecovery`) live in the manager module that
  consumes them, next to the trait, following `services/payments/manager.rs`.
  The validated forms they wrap (`EventAttendanceInput`, `CheckoutInput`,
  `EventInput`, `EventActionScope`) live in `types/`.

Placement inside `types/`:

- A type shared by two or more dashboard sections, or by the public site,
  lives in a domain module (`types/event.rs`, `types/group.rs`).
- A type used by exactly one dashboard section lives in
  `types/dashboard/<scope>/<section>.rs`, mirroring
  `handlers/dashboard/<scope>/<section>.rs`.
- A type is promoted to a domain module when its second consumer appears,
  not before. `PageViewsStats` (`types/analytics.rs`) and
  `CfsSessionProposal` (`types/event.rs`) are shared by the community and
  group analytics pages and by the group and user submission views.
- Dashboard list defaults (`DASHBOARD_PAGINATION_LIMIT`, `default_limit`,
  `default_offset`) live in `types/dashboard.rs` next to the `*Filters` that
  use them.
- The group and community team projections stay separate types
  (`GroupTeamMember`/`GroupTeamOutput`, `CommunityTeamMember`/
  `CommunityTeamOutput`): they already diverge (`is_admin` exists only for
  groups) and no consumer handles both uniformly, so a generic
  `TeamMember<R>` would couple them without a reader.
- `DBDashboardGroup` is not split into section traits: no non-mock consumer
  accepts a narrower trait than `DBOperations`, so a split would reorganize
  declarations without narrowing any dependency or mock surface. Revisit when
  a service can take a section trait.

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

Template structs that are only rendered do not derive them. The explore
`EventCard` and `GroupCard` keep `Serialize` because the results templates
embed them through the `json` filter for the calendar and map scripts.

Persisted notification payloads are a compatibility contract.
`templates::notifications::*` structs are stored as `template_data` and read
back by `DeliveryWorker::prepare_content` after deployment. Each of these
structs implements `templates::notifications::NotificationTemplate`, which
owns the email subject and the completion of stored root-relative URLs with
the deployment base URL; `prepare_content` only maps a `NotificationKind` to
its struct and renders it through that trait. Moving or renaming one of
these types must not change its serialized form. Removing a field, changing
a field's meaning, or evolving an enum requires an explicit decision recorded
in the PR and, when incompatible, a conversion step in `prepare_content`.
Fixtures for supported older shapes live in
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

- `services::badges::BadgesManager` (`SsiBadgesManager`), which signs,
  caches, and verifies Open Badges credentials with locally configured keys.
- `services::enrollment::EnrollmentManager` (`PgEnrollmentManager`): event
  attendance, checkout, self-service and organizer cancellation, organizer
  invitations and request acceptance, and group membership.
- `services::events::EventsManager` (`PgEventsManager`): organizer event
  mutations (add, update, publish, unpublish, cancel, delete, series
  expansion in `services/events/recurrence.rs`), fiscal sponsor validation
  before paid changes, and automatic-tax readiness and Tax Rate lookups.
- `services::notifications::NotificationsManager` (`PgNotificationsManager`)
  with the `EmailSender` provider trait.
- `services::payments::PaymentsManager` (`PgPaymentsManager`) with the
  `PaymentsProvider` trait and the webhook reconciler, refund recorder, and
  notification composer around it. It owns checkout hold preparation
  (`prepare_checkout`) and payment job recovery
  (`complete_payment_job_recovery`) so no handler builds `db::payments`
  operation types.
- `services::meetings::MeetingsProvider`, keyed by provider in
  `DynMeetingsProviders`.
- `services::images::ImageStorage`.

Everything that does not warrant a manager is a free function over
`&dyn DBOperations` in `services/`, or stays in the handler when it is
request shaping only: `services::images::validation` (upload format,
extension, SVG, and dimension checks), `services::badges::verify_submission`
(credential verification bound to durable awards), `services::check_in`
(credential parsing and scan rejection classification), and the notification
helpers in `services::notifications::{enqueue, payloads, best_effort}`.

Manager wiring follows `setup_payments_manager` in `main.rs`; handler tests
inject mocks through `TestRouterBuilder::with_*_manager`, whose defaults
expect no calls.

### Worked example: `EnrollmentManager::attend_event`

`handlers/event.rs::attend_event` extracts `CurrentUser`, `CommunityId`, the
event path parameter, and `ValidatedForm<EventAttendanceInput>`; it calls
`enrollment_manager.attend_event(&AttendEventInput { .. })` and maps the returned
`AttendOutcome` to the response:

| Outcome | Status | Body |
| --- | --- | --- |
| `Conflict(code)` | 409 | `{"conflict": code}` |
| `Enrolled(status)` | 200 | `{"status": status}` |
| `ExternalPendingPayment(checkout)` | 200 | payment snapshot |
| `CheckoutRedirect { .. }` | 200 | `redirect_url`, `hold_expires_at` |

The manager owns everything else: the active-event guard, the single-ticket
fallback, the deferred-answers rule for sold-out waitlist tickets, the
`attend_event` call, the answers re-collection conflict, the checkout hold
through `PaymentsManager::prepare_checkout`, free completion, the provider
redirect, and the best-effort waitlist notification. Conflict codes are the
kebab-case `Display` of the `db` conflict enums, so the manager returns
`Conflict(String)` and handlers never import a `db` type.

Manager methods return a typed error with exactly two variants,
`Rejected(String)` and `Other(anyhow::Error)` (`EnrollmentError`,
`EventsError`, `PaymentsError`). `Rejected` is a business decision made in
Rust; `Other` wraps database and provider failures unchanged so
`HandlerError::from(anyhow::Error)` can still classify `OCG01` rejections.
Provider errors with their own user-facing variants
(`FiscalSponsorReadinessError`, `AutomaticTaxReadinessError`) convert into
the manager error with `From`, mapping correctable variants to `Rejected`.
The explicit readiness check is the one exception: it returns
`AutomaticTaxCheckError`, whose `Readiness` variant carries the full
`AutomaticTaxReadinessError` for the endpoint's JSON contract and whose
`Other` variant keeps context-loading failures (event, fiscal sponsor) on
the regular `HandlerError::from(anyhow::Error)` path, so a database failure
is never reported as a provider outage.

Event mutations keep the JSON payload produced by `EventInput::to_db_payload`
as the contract with the database: `services/events/recurrence.rs` shifts the
nested schedule fields of that payload for each occurrence, and
paid-capability detection reads the same shape. A typed
`Unchanged | Clear | Set(T)` mutation was evaluated and not adopted because
the payload is produced and consumed inside the manager and the database
function is the only reader.

Pure eligibility predicates take the clock as a parameter: the manager reads
`Utc::now()` once per operation and passes it to
`cancellation_notification_events`, `publication_notification_events`,
`enqueue_event_rescheduled_notification`, and `EventSummary::is_past_at`.
The `Utc::now()` convenience wrappers on `types/event.rs` stay for templates
and delegate to the `*_at(now)` variants.

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
  fails the core operation. Best-effort event notifications go through
  `services::notifications::best_effort::enqueue_event_notification_best_effort`,
  which loads the event and site context, calls the supplied
  `payloads::build_*` builder, enqueues through `NotificationsManager`, and
  logs any failure. Best-effort notifications outside the event context have
  their own named helper in the same module
  (`enqueue_cfs_submission_updated_best_effort`,
  `enqueue_community_team_invitation_best_effort`,
  `enqueue_group_team_invitation_best_effort`); each loads its context,
  builds its payload, enqueues, and logs, so the handler passes identifiers
  only. `GroupWelcome` is enqueued by `EnrollmentManager::join_group`.

Enqueue helpers own the notification content; callers pass identifiers and
configuration. Content assertions live with the helper, not with the caller.
Organizer-authored custom notifications go through
`enqueue::enqueue_tracked_{event,group}_custom_notification`, which build the
`CustomNotificationTracking` audit record; the password sign-up verification
payload comes from `payloads::build_email_verification_notification`. No
handler constructs a `db`-owned notification type.

A generic `Notifier` abstraction over required and best-effort notifications
was evaluated and not adopted: no caller needs to be generic over the
notification kind, so the named `enqueue::*` functions plus the best-effort
helper are the final shape. `PaymentsNotificationComposer` keeps its own
composition path.

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
  `HandlerError::Other(err)` directly. Wrapping directly turns an `OCG01`
  rejection raised inside the service into a 500. Its user-facing variants
  map to `Rejected` (`FiscalSponsorReadinessError::NotReady`,
  `AutomaticTaxReadinessError` correctable variants).
- `Deserialization` carries parser output that is never returned to the
  client. `HandlerError::into_response` logs it and answers with the fixed
  body. The `ValidatedForm`, `ValidatedFormQs`, and `ValidatedQuery`
  extractors, `From<serde_qs::Error>`, and `FilterError::Parse` all use this
  variant; `garde` failures (the extractors' `validate()` step, `FilterError::
  Validation`) keep returning the field-level report through `Validation`.
- `Auth` carries no payload. Callers that need the underlying cause in logs
  record it before mapping.
- Internal detail (database errors, provider errors, panics) is logged
  through the handler span and never written to the response body.

## Handler shape

A handler does extraction, delegation, and response shaping, in this order:

1. **Extraction**: path, query, and form data through the typed extractors
   in `handlers/extractors.rs`. Extractors deserialize and run `garde`
   validation; a handler does not re-validate.

   | Extractor | Source | Yields |
   | --- | --- | --- |
   | `CurrentUser` | auth session | logged-in `User`, else 401 |
   | `CommunityId` | `{community}` path parameter | community id, else 404 |
   | `SelectedCommunityId` | extensions set by middleware | selected community |
   | `SelectedGroupId` | extensions set by middleware | selected group |
   | `ValidatedForm<T>` | flat form body | validated `T` |
   | `ValidatedFormQs<T>` | nested form body (`serde_qs`) | validated `T` |
   | `ValidatedQuery<T>` | query string (`serde_qs`) | validated `T` |
   | `OAuth2`, `Oidc` | `{provider}` path and auth backend | provider details |

   A handler that reads the query string for its own use takes
   `ValidatedQuery<T>`. `RawQuery` remains only where the raw string is
   forwarded: the dashboard `home` pages hand it to the selected tab's
   `prepare_*` helper (the tab, and therefore the filter type, is only
   known at runtime), and the explore handlers hand it to
   `Search*Filters::new`, which also needs request headers. A shared
   `prepare_*` helper parses the forwarded string with
   `ValidatedQuery::<T>::parse`, so the deserialization and validation
   contract has a single implementation.
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

Handlers that open a transaction directly are limited to single-write
operations with no side effects (`submit_registration_answers`); every
multi-step workflow is behind a manager. Response-only concerns stay in the
handler: HTMX headers, the `AutomaticTaxReadiness*` JSON contract, the
check-in scanner error envelope, and the "exactly one invite target" `400`.

## Test layering

Each behavior is proven at the cheapest layer able to prove it. The mock
surface per layer:

- Handler (`handlers/**/tests.rs`): mocks managers and `MockDB` for reads
  and session; asserts status, headers, body, and the identifiers passed to
  the manager or notifier.
- Manager and service (`services/**/tests.rs`): mocks `MockDB`, providers,
  and `MockNotificationsManager`; asserts workflow order, commit or
  rollback, and side effects enqueued or suppressed.
- Notification helper (`enqueue.rs` tests, `best_effort/tests.rs`,
  `payloads.rs` tests): mocks `MockDB` and `MockNotificationsManager`;
  asserts notification kind, recipients, `template_data` content, and the
  tracking record.
- Error contract (`handlers/error/tests.rs`): no mocks; asserts each
  `HandlerError` variant's status and body.
- Contract (`db/contract_tests`): real database; asserts SQL JSON to Rust
  DTO shapes and the `PgUnitOfWork` lifecycle.

- **Handler tests** build the router with `TestRouterBuilder`, mock managers
  and `MockDB`, and assert status, headers, and body. Session and permission
  setup uses the shared helpers (`expect_authenticated_session`,
  `expect_authenticated_community_session`,
  `expect_authenticated_group_session`, `expect_community_permission`,
  `expect_group_permission`); the remaining direct transactions use
  `expect_successful_transaction`. A handler behind a manager has one or two
  manager expectations per test and no workflow `MockDB` expectations. Every
  typed manager error is proven at the handler through the mock with three
  tests: an `OCG01` database rejection (an `Other` wrapping
  `HandlerError::Database`) returns 422 with its message, a `Rejected`
  returns 422 with its message, and an internal failure returns 500 with an
  empty body.
- **Handler DB-failure tests** exist only when they prove something the error
  contract tests cannot: a failure mapped to a non-500 status, a suppressed
  later side effect, or an error path outside `HandlerError` (permission
  middleware, extractors). A mutation handler followed by a side effect
  (notification enqueue, flash message, session write) keeps one DB-failure
  test that fails the write and asserts the side effect and its context
  reads with `.never()`, so the write-then-notify order is asserted rather
  than inferred from unconfigured mocks. A handler that only propagates a
  direct `DynDB` read or write with `?` and then responds has no per-route
  `*_db_error` test; `handlers/error/tests.rs::
  test_non_db_anyhow_error_returns_500` proves the mapping once.
- **Manager and service tests** mock `MockDB` and the provider traits and
  assert workflow order, commit or rollback (through `expect_begin` with a
  transaction `MockDB` whose `commit` or `rollback` is expected), provider
  validation before any write, and which side effects were enqueued. Manager
  tests do not import `handlers`; they keep their own transaction helpers and
  sample builders.
- **Notification content** (`template_data` fields, links, theme, tracking
  record) is asserted in the notification helper tests: the `tests` module of
  `services/notifications/enqueue.rs` for required and tracked
  notifications, `services/notifications/best_effort/tests.rs` for
  best-effort ones, and the `tests` module of `payloads.rs` for pure
  builders. Callers, including handler tests, assert only the notification
  kind, recipients, and tracking identifiers.
- **Shared sample builders** for domain types (`sample_event_summary`,
  `sample_event_full`, `sample_site_settings`, and similar) live in
  `types/tests.rs`; `handlers/tests.rs` re-exports them next to the handler
  harness, and `services` or `templates` tests import them from
  `types::tests` so test code follows the same dependency direction.
- **Real JSON contracts** between SQL functions and Rust DTOs are asserted in
  `db/contract_tests` against a real database (`just db-contract-tests`).
- **Real-database lifecycle behavior** that mocks cannot prove runs with
  `just db-contract-tests`. `db/contract_tests/lifecycle.rs` proves the
  `PgUnitOfWork` contract: a dropped transaction future rolls back and
  returns a clean connection to the pool, an explicit `rollback` leaves
  nothing visible, and a `commit` that trips a deferred constraint fails and
  persists nothing. Manager compositions live next to the manager
  (`services/enrollment/manager/contract_tests.rs`) and reuse the
  `db::contract_tests::helpers` fixtures: the organizer cancellation commits
  together with its required notification, and a failing required enqueue
  rolls the attendance change back.

A handler test is removed only when the PR description carries a
replacement mapping: each deleted test listed next to the manager, notifier,
or error test that proves the same behavior (same failing call, same rollback
or suppressed side effect, same status). A test with no replacement stays.
Test counts are reported for information and never decide.

## Bounded operations and worker health

Rule: every call that leaves the process has a connection deadline and a
total-operation deadline set at the boundary that owns the client, and a
timed-out write is classified by whether the external outcome is known (a call
with a deterministic idempotency key is retryable; one without follows the
unknown-outcome path such as `mark_notification_delivery_unknown` or payment
reconciliation, never a blind retry).

### Outbound deadlines

Deadlines come from typed configuration under the section that owns the
client. Every HTTP client is built once through `util::build_http_client`
from an `HttpClientConfig { connect_timeout_secs, request_timeout_secs }`
(defaults 10s and 30s, both at least 1); the request deadline covers the whole
exchange including the response body.

- Stripe API: `payments.http_client`, built in `StripeProvider::new`.
- Zoom API: `meetings.zoom.http_client`, built in `ZoomClient::new`.
- `OAuth2` and OIDC token exchange plus the GitHub profile and email loaders:
  `server.http_client`, built in `AuthnBackend::new`.
- SMTP: `email.smtp.connect_timeout_secs` bounds session establishment and
  `email.smtp.send_timeout_secs` bounds one complete delivery attempt, both
  applied by `LettreEmailSender`.
- PostgreSQL connection creation: the pool `create` timeout (10s) applied by
  `db::pool::config_with_defaults`, alongside the `wait` and `recycle`
  timeouts.
- PostgreSQL statements: `config_with_defaults` sends
  `statement_timeout=30000` and `idle_in_transaction_session_timeout=60000` as
  session startup options unless `db.connection.options` is set. Both are
  enforced by the server: a statement that exceeds the deadline (including
  time spent waiting on a lock) is cancelled and its transaction rolled back
  before the client sees `57014`, and a session left idle inside a transaction
  is closed. Startup options are the session defaults, so `DISCARD ALL` on
  recycle keeps them. A path that legitimately needs longer must raise the
  limit with `set local statement_timeout` inside its own transaction.

Timed-out writes are classified at the boundary:

- Every Stripe write carries a deterministic idempotency key, so a request
  that hits the deadline surfaces as an error and is retryable: durable
  payment jobs release their claim through `record_payment_job_failure` and
  are claimed again; a checkout session retry reuses the same key.
- An SMTP delivery attempt that exceeds `send_timeout_secs` is
  `EmailDeliveryError::Unknown` and is recorded through
  `mark_notification_delivery_unknown`; the message may already have been
  accepted, so it is never retried blindly. A connection that times out before
  the session is established is `Retryable`, like any other connection
  failure.
- A Zoom meeting creation has no idempotency key, so `ZoomMeetingsProvider`
  makes the retry itself safe instead: every meeting is created with its
  `agenda` set to `ocg:event:<event_id>` or `ocg:session:<session_id>`, and
  before creating, the provider lists the scheduled meetings of every host in
  `meetings.zoom.host_pool_users` looking for that marker. A match is adopted
  (updated to the current meeting state and re-read for its join details) and
  reported with the host that owns it, so a creation whose response was lost
  never produces a second Zoom meeting. Zoom deletes and updates are
  idempotent, and `OAuth2`, OIDC, and GitHub calls are reads or the caller
  retries them as a whole (the login flow); a timeout surfaces as the request
  failing.
- A PostgreSQL statement timeout is not an unknown outcome: the server aborts
  the statement, so the write did not happen. The only ambiguous case is a
  commit whose acknowledgement is lost on the network, which the durable job
  claims and stale-claim recovery already cover.

### Workers and shutdown

Workers are built on `services/workers.rs`: `run_worker` drives
cancellation-aware iterations, `claim_loop` claims and releases jobs, and
`BackgroundTasks` spawns and observes workers.

- `BackgroundTasks::spawn` takes a worker name (`notifications-delivery`,
  `payments-jobs`, `activity-flusher`, ...). Several instances may share a
  name. The worker runs as its own task; a tracked monitor awaits it and
  records how it ended in the shared `WorkerRegistry`: a return after
  cancellation or an abort during shutdown is an expected stop, a return
  before cancellation or a panic is an unexpected exit and is logged with the
  worker name (and the panic message). Workers are not restarted
  automatically; a dead worker stays dead until the process restarts, and the
  error log line is the alert.
- Worker state is deliberately kept out of the health probe. `/health-check`
  answers whether the process can serve requests, which background workers do
  not affect; tying a probe to worker exits would remove serving capacity
  without healing anything. Worker state is reported through the periodic
  health log instead.
- `BackgroundTasks::shutdown` cancels every worker and waits up to
  `server.shutdown_grace_period_secs` (default 30) for them to finish their
  in-flight unit; workers still running when the grace period expires are
  aborted. A job left in `processing` by an aborted worker is recovered by the
  existing stale-claim recovery workers on the next start. Idle workers stop
  as soon as they observe cancellation, so an idle shutdown does not consume
  the grace period. The notification delivery worker's pause between send
  retries is cancellation-aware: a shutdown request during the pause releases
  the claim through `release_notification` instead of recording a delivery
  outcome.

### Signals and identifiers

Operational signals go through tracing, the only telemetry path the server
has:

- The `queue-health` worker (`services/workers/queue_health.rs`) logs every
  five minutes: per durable job queue (`badge_award_jobs`, `notifications`,
  `payment_jobs`), the pending and processing counts and the age of the oldest
  pending job (read through `get_worker_queue_health`); and per worker name,
  the running instances and the number of unexpected exits. The meetings and
  enrollment workers scan domain rows for due work rather than a job table
  and have no backlog signal.
- Unexpected worker exits are logged when they happen, with the worker name
  and the panic message.
- Notification delivery outcomes are logged with `notification_id`, `kind`,
  and `outcome` (`retryable`, `terminal`, `unknown`); the terminal and
  unknown lines are errors.
- Activity events dropped since the previous flush are logged by the
  aggregator as a warning.
- Payment job failures are logged with `payment_job_id` and `attempt_count`
  when the claim is released.

Stable identifiers make a failure reconstructible across spans: every request
gets an `x-request-id` (generated when the client sends none, echoed in the
response) that is a field of the request span; `enqueue_notification` returns
the identifiers it created and the wrapper logs them with the kind inside the
enqueue span; the delivery worker logs the same `notification_id` on every
outcome.

### CPU-heavy work

CPU-bound work runs off the async executor through
`services::blocking::BlockingExecutor`, which wraps `spawn_blocking` in a
semaphore sized by `server.max_blocking_concurrency` (default: the host's
available parallelism, at least 1). Callers await a permit before their
closure is handed to the blocking pool and the permit is released when the
closure completes, so a burst cannot saturate the pool. One executor is
created in `router::setup` and shared by the router state (sign-up and
password update hashing in `handlers/auth.rs`) and `AuthnBackend` (password
verification). A panic inside the closure surfaces as an error to the caller.

### Bounded exports

The attendee CSV exports (`handlers/dashboard/group/attendees.rs`) load the
exported rows and build the file in memory, so their size is bounded
explicitly rather than streamed. The export requests confirmed attendees only
with `limit = MAX_ATTENDEES_EXPORT_ROWS` (10,000) and rejects the request with
`HandlerError::Rejected` when the confirmed total exceeds that bound. The
supported size was chosen from a measurement at 10,000 rows with long names,
companies, payment details, and registration answers: the database JSON
payload is about 13.5 MB, the CSV about 1.9 MB, and process RSS grows by about
38 MB while the export is built. A new export follows the same pattern: state
the supported row count, measure memory at that size, and adopt streaming only
when the measured cost is unacceptable.

### Lossy best-effort pipelines

A best-effort pipeline states whether it is lossy or durable and what
saturation does to its callers. The activity tracker
(`src/activity_tracker.rs`) is **deliberately lossy**: page-view analytics
never delay or fail a request.

- `track` uses `try_send` on a bounded queue (10,000 activities). A full or
  closed queue drops the activity and increments the shared
  `ActivityTrackerStats::dropped_events` counter; the call still returns
  `Ok`.
- The aggregator caps one batch at `MAX_BATCH_KEYS` (10,000) distinct
  `(entity, day)` keys across all activity kinds. An activity that would add a
  key beyond the cap is dropped and counted; activities for keys already in
  the batch keep aggregating.
- The aggregator hands batches to the flusher with `try_send` on a single-slot
  queue. When the flusher is still busy at flush time, the aggregator logs a
  warning, keeps the batch, and continues merging activities into it until the
  next flush; it never blocks on the flusher, so a slow database only delays
  writes instead of stalling the activities queue.
- The flusher logs a failed database write and drops the affected counters;
  the remaining counters in the batch and later batches are still written.
- On shutdown the aggregator drains what is queued and hands the final batch
  to the flusher; if the flusher is congested, the worker is aborted at the
  end of the shutdown grace period like any other stalled worker.
- Drops are reported through tracing: the aggregator logs a warning with the
  number of activities dropped since the previous flush and the running total.

## Cached reads and transactions

Rule: a `#[cached]` read caches data that is long-lived and that no
transaction mutates before reading back. The cache is a performance tool for
reference data (`get_site_settings`, community lookups, kinds, roles,
currency codes, timezones, dashboard statistics, notification attachments),
not a consistency mechanism.

The `#[cached]` reads sit on blanket `impl<T: PgExecutor>` blocks, so `PgDB`
and `PgUnitOfWork` share the same cache entries and there is no transactional
bypass. A cached read inside a transaction is served from the cache like any
other call, and a miss populates the cache from the transaction's view.
Bypassing the cache for every transactional read was considered and rejected:
it makes each such call a database round-trip that is invisible at the call
site, and no current transaction reads a cached value it has written.

Consequences:

- Code that reads a cached value after writing it inside the same
  transaction must not rely on seeing its own write.
- A new `#[cached]` read is added only for data that transactions never
  mutate before reading. If such a path is needed, read the row directly
  with an uncached query rather than adding a bypass to the cached method.
- Acceptable staleness is the cache TTL; invalidation is unchanged.

Cache entries are keyed by the data they describe (a constant for singletons
such as `site_settings`, otherwise the row identifier) and are global to the
process. Every `PgDB` in a process shares them, which is the intended
production shape (one pool, one database).

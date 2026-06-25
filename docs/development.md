# Development Guide

This guide is for contributors working on the GOUP application codebase. For
local setup commands, configuration examples, and EC2 deployment commands, start
with the root [README](../README.md).

## System Architecture

GOUP is a server-rendered Rust application with focused client-side
enhancements.

- **HTTP server:** `ocg-server` uses Axum for routing, middleware, sessions, and
  request extraction.
- **HTML rendering:** Askama templates under `ocg-server/templates/` render
  pages, dashboard fragments, emails, and reusable macros.
- **Interactivity:** HTMX handles most dashboard form submissions and partial
  refreshes. Browser-side modules in `ocg-server/static/js/` provide richer
  controls such as markdown editors, image upload fields, selectors, charts, and
  confirmation flows.
- **Data layer:** PostgreSQL stores normalized application data. SQL functions
  in `database/migrations/functions/` keep complex data operations close to the
  schema and are called through Rust DB traits.
- **Background work:** Notification delivery, reminders, payment flows, and
  meeting integrations run from services under `ocg-server/src/services/`.
- **Operations:** The production EC2 deployment pulls from `main`, runs
  migrations, builds the release binary, and restarts systemd services. The
  optional MCP server exposes authenticated operational tools.

## Repository Map

```text
.
├── database/migrations/        # Schema, reference data, SQL functions, migration loader
├── docs/                       # User, operator, and contributor documentation
├── mcp/                        # Remote MCP server and tool catalog
├── ocg-redirector/             # Small redirect service
├── ocg-server/                 # Main web application
│   ├── src/auth.rs             # Login/session backend and auth user model
│   ├── src/db/                 # DB traits and PostgreSQL adapters
│   ├── src/handlers/           # Axum route handlers
│   ├── src/router/             # Route registration and permission middleware
│   ├── src/services/           # Notifications, payments, meetings, images, jobs
│   ├── src/templates/          # Typed Askama template view models
│   ├── static/                 # Browser JS, CSS sources, vendored assets
│   └── templates/              # Askama HTML and email templates
└── tests/
    ├── e2e/                    # Playwright browser tests
    └── unit/                   # Frontend unit tests
```

## Request Lifecycle

Most pages follow the same path:

1. A route is registered in `ocg-server/src/router/`.
2. Middleware checks authentication and alliance/group permissions when needed.
3. A handler in `ocg-server/src/handlers/` extracts request state and form data.
4. The handler calls a DB trait method from `ocg-server/src/db/`.
5. The PostgreSQL adapter runs a query or SQL function from
   `database/migrations/functions/`.
6. The handler builds a typed template struct from `ocg-server/src/templates/`.
7. Askama renders HTML from `ocg-server/templates/`.
8. HTMX either swaps a dashboard fragment or navigates the full page.

Prefer this existing flow for new features. It keeps validation, permissions,
and rendering consistent across dashboards.

## Backend Patterns

Handlers should stay thin: validate input, authorize the current actor, call DB
or service methods, and render a response. Larger business rules should live in
database functions or service modules depending on ownership:

- Use **database functions** for transactional mutations, eligibility checks,
  audit logging, reference data lookups, and operations that need to remain
  close to constraints.
- Use **Rust services** for external systems, background work, email rendering,
  payment provider orchestration, image storage, and meeting APIs.
- Use **typed template structs** for view data rather than passing loose maps to
  templates.

The DB layer is trait-based so handlers can be tested with generated mocks. When
adding a DB method, update the relevant trait and the mock definition.

## Frontend Patterns

Dashboard pages are server-rendered and progressively enhanced.

- Use HTMX attributes for form submissions, table refreshes, and fragment
  updates.
- Use shared custom elements for repeated controls:
  `markdown-editor`, `image-field`, `gallery-field`, `multiple-inputs`,
  selectors, and team role forms.
- Keep plain form field names aligned with Rust input structs.
- Prefer existing dashboard macros in `ocg-server/templates/macros/` before
  adding new markup patterns.

For image inputs, use `image-field` instead of a plain URL field when users
should be able to upload files. It still writes a URL into the form payload, so
existing `*_url` storage can usually stay unchanged.

## Database and Migrations

Schema and function changes belong under `database/migrations/`.

- Put schema/reference data changes in `database/migrations/schema/`.
- Put SQL functions in `database/migrations/functions/` and include them from
  `database/migrations/functions/001_load_functions.sql`.
- Keep migrations idempotent when reasonable with `if not exists` and
  `on conflict` patterns.
- Update pgTAP tests and Rust database contract tests when changing database
  behavior.

Run migrations from `database/migrations`:

```bash
cd database/migrations
TERN_CONF="$HOME/.config/ocg/tern.conf" ./migrate.sh
```

## Authentication and Permissions

Authentication supports email/password, GitHub OAuth2, and LinkedIn OIDC,
depending on server configuration. Session state stores the selected alliance
and group so dashboards can operate without repeating IDs in every URL.

Permission checks are layered:

- Route middleware protects broad dashboard access.
- Handlers check narrower write permissions before mutating data.
- SQL functions and constraints enforce invariants that must hold even if a
  caller changes.

Use the existing `AlliancePermission` and `GroupPermission` variants where
possible.

## Notifications

Notifications are queued as typed `NotificationKind` values with JSON template
data. The delivery worker renders Askama email templates and sends mail through
the configured email provider.

When adding a notification:

1. Add or reuse a `NotificationKind`.
2. Add a typed template data struct in `ocg-server/src/templates/notifications.rs`.
3. Add an Askama email template under `ocg-server/templates/notifications/`.
4. Add database reference data if the kind is new.
5. Add rendering tests in `ocg-server/src/services/notifications/tests.rs`.

Queued template data should remain backward-compatible when possible because
notifications can be delivered after code changes.

## Testing Checklist

Use the smallest check that covers the risk, then broaden when shared behavior
changes.

```bash
cargo check -p ocg-server
cargo clippy --all-targets --all-features -- --deny warnings
just server-tests
just db-tests
just db-contract-tests
just frontend-unit-tests
just e2e-tests
```

Useful focused examples:

```bash
cargo test -p ocg-server test_delivery_worker_prepare_content_site_onboarding
cargo test -p ocg-server handlers::auth::tests::test_sign_up_success
```

## Deployment Notes

Production EC2 updates are currently pull-and-rebuild deployments:

```bash
cd ~/goup.vc
git pull origin main
cd database/migrations
TERN_CONF="$HOME/.config/ocg/tern.conf" ./migrate.sh
cd ~/goup.vc
nohup env CARGO_BUILD_JOBS=1 cargo build --release -p ocg-server > ~/goup-build.log 2>&1 &
tail -f ~/goup-build.log
sudo systemctl restart ocg-server
sudo systemctl status ocg-server --no-pager
curl -I http://127.0.0.1:9000
```

Only run the MCP restart when files under `mcp/` changed:

```bash
sudo systemctl restart goup-mcp
sudo systemctl status goup-mcp --no-pager
```

## Common Pitfalls

- Run `database/migrations/migrate.sh` from the `database/migrations` directory.
  Running it from the repository root can fail because the script expects local
  migration folders.
- Do not add raw HTML editing for emails unless it is explicitly required.
  Prefer structured fields rendered by trusted templates.
- Keep HTMX search forms from re-rendering on every keystroke when the server
  normalizes input, otherwise trailing spaces can disappear while typing.
- Preserve user or teammate work in a dirty tree. Stash or branch before
  isolating unrelated fixes.

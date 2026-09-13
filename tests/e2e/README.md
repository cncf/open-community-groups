# E2E Tests

Playwright end-to-end tests for Open Community Groups. They run against a real
server and a dedicated PostgreSQL database seeded with fixed test data.

## Prerequisites

- Node.js 22+
- PostgreSQL 17+ with `pgcrypto` and `postgis`
- Rust toolchain
- `tailwindcss`, `tern` (2.3.0+) and `just` on `PATH`

## Running the Suite

```sh
# Install Playwright and browsers
just e2e-install

# Drop, create, migrate and seed the e2e database
just e2e-db-reset

# Start the e2e server (keep it running in another terminal)
just e2e-server

# Run all tests
just e2e-tests
```

Seeded `e2e-*` users log in with the password `Password123!`.

Other useful commands:

```sh
# One spec file (path relative to tests/e2e), extra flags go to Playwright
just e2e-tests-file dashboard/common/session.spec.js --project=chromium-deep

# One project
just e2e-tests --project=chromium-smoke

# Playwright UI / headed browser
just e2e-tests --ui
just e2e-tests --headed

# Update visual snapshots
just e2e-update-snapshots

# Server with auto-reload, and a psql session on the e2e database
just e2e-server-watch
just db-client-tests-e2e
```

Format the suite with `just frontend-fmt-and-lint`.

## Configuration

All recipes, the server, tern, psql and Playwright share these variables,
exported by the `justfile`:

| Variable              | Default                 |
| --------------------- | ----------------------- |
| `OCG_E2E_DB_HOST`     | `OCG_DB_HOST`           |
| `OCG_E2E_DB_PORT`     | `OCG_DB_PORT`           |
| `OCG_E2E_DB_USER`     | `OCG_DB_USER`           |
| `OCG_E2E_DB_PASSWORD` | `OCG_DB_PASSWORD`       |
| `OCG_E2E_DB_NAME`     | `ocg_tests_e2e`         |
| `OCG_E2E_BASE_URL`    | `http://127.0.0.1:9001` |

`OCG_PG_BIN` optionally points at a PostgreSQL `bin` directory (default:
Homebrew PostgreSQL 17). The `justfile` prepends it to `PATH` for psql and
Playwright recipes; `tests/e2e/database.js` reads it directly when Playwright
runs outside `just`.

`OCG_E2E_DB_NAME` must end in `_e2e`; destructive recipes and
`tests/e2e/database.js` refuse any other name. The server profile is
`config/server.yml` (fake Stripe and Zoom credentials) and the tern
configuration is `config/tern.conf`.

Before the first test, `preflight.js` checks `/health-check` and compares a
marker written by `just e2e-db-reset` with the one the server renders. If
they differ, the server and psql point at different databases.

## Projects

- `chromium-smoke`, `firefox-smoke`, `webkit-smoke`: the smoke specs listed
  in `playwright.config.js`.
- `chromium-deep`: every other spec on desktop Chromium.
- `chromium-mobile-deep`: tests tagged `@mobile` on a mobile device.

Visual tests are tagged `@visual`; snapshots live next to their spec in
`*.spec.js-snapshots/`.

CI runs the same recipes: one job per smoke browser, six functional shards
(`--grep-invert @visual --shard=N/6`) and one visual job. To reproduce a shard:

```sh
just e2e-tests --project=chromium-deep --project=chromium-mobile-deep \
  --grep-invert @visual --shard=1/6
```

## Writing Tests

- Folders: `site/` (public pages), `dashboard/` (dashboard tabs), `workflows/`
  (flows across roles or surfaces) and `visual/` (screenshots).
- Shared helpers: `utils.js` (navigation, `uniqueName`, `futureDate`),
  `seed.js` (seeded IDs and credentials), `database.js` (psql queries),
  `notifications.js`, `webhooks.js`, `data-graphs/` (disposable data graphs) and
  per-folder `helpers.js`.
- Seeded rows are read-only. A test that mutates data owns the rows it creates
  or changes and restores them by ID in `finally`, so any spec passes with
  `--repeat-each=5 --retries=0` without reseeding.
- Rows created through the browser use `uniqueName()` and `futureDate()`;
  do not use `Date.now()`.
- Worker-owned transitions (payments, badges) are awaited with `expect.poll`
  and include the job row status in the failure message.
- Notification checks snapshot the `notification` table, act, assert the new
  rows by kind and recipient, and delete them. Email delivery is not asserted.
- Stripe and Zoom are covered through signed webhooks only; flows that need the
  real providers (for example `checkout.session.completed`) are out of scope.

## Troubleshooting

- Preflight failure: run `just e2e-db-reset`, restart `just e2e-server` and
  make sure both use the same `OCG_E2E_*` values.
- Navigation errors: check `<OCG_E2E_BASE_URL>/health-check` responds.
- Port `9001` busy: start the server with `OCG_SERVER__ADDR=127.0.0.1:9002`
  and set `OCG_E2E_BASE_URL` to match.
- `OCG_E2E_START_SERVER=true` lets Playwright start the server itself
  (`OCG_E2E_SERVER_CMD`, `OCG_E2E_SERVER_TIMEOUT`, `OCG_E2E_REUSE_SERVER`).
- Keep `package-lock.json` committed and use `npm ci` so browser versions stay
  pinned for visual snapshots.

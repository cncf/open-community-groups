# E2E Tests

End-to-end tests for Open Community Groups using Playwright.

## Prerequisites

- Node.js 22+
- PostgreSQL 17+ with `pgcrypto` and `postgis`
- Rust toolchain
- `tailwindcss` on `PATH`
- `tern` on `PATH`
- `just`

`just e2e-install` installs Playwright and browsers, but it does not install
`tailwindcss` or `tern`.

## Quick Start

```sh
# Install e2e dependencies from tests/e2e/package.json
just e2e-install

# Recreate and migrate the e2e test database
just db-recreate-tests-e2e

# Load the e2e seed data into the e2e test database
just db-load-tests-e2e-data

# Start the e2e server in another terminal
just e2e-server

# Run the Playwright suite
just e2e-tests
```

`just db-load-tests-e2e-data` also normalizes the seeded `e2e-*` user
passwords to the credentials expected by the Playwright suite.

## Common Commands

```sh
# Recreate and migrate the e2e test database
just db-recreate-tests-e2e

# Load the e2e seed data into the e2e test database
just db-load-tests-e2e-data

# Start the e2e server
just e2e-server

# Start the e2e server with auto-reload
just e2e-server-watch

# Run the full Playwright suite
just e2e-tests

# Update visual snapshots
just e2e-update-snapshots

# Run a specific Playwright project
cd tests/e2e; npx playwright test --config playwright.config.ts --project=chromium-smoke

# Open the Playwright UI
cd tests/e2e; npx playwright test --config playwright.config.ts --ui

# Run with a visible browser
cd tests/e2e; npx playwright test --config playwright.config.ts --headed
```

## Configuration

Most runs only need:

- `OCG_E2E_BASE_URL`
  Base URL used by Playwright. Default: `http://localhost:9001`.
- `OCG_E2E_MEETINGS_ENABLED`
  Enables automatic meeting coverage and assertions. `just e2e-tests` sets this
  to `true` by default. Use `false` to disable it for a custom run.
- `OCG_E2E_PAYMENTS_ENABLED`
  Enables payment-specific coverage and assertions. `just e2e-tests` sets this
  to `true` by default. Use `false` to disable it for a custom run.

Useful test data overrides:

- `OCG_E2E_COMMUNITY_NAME`
- `OCG_E2E_GROUP_SLUG`
- `OCG_E2E_EVENT_SLUG`

Playwright server management:

- `OCG_E2E_START_SERVER`
- `OCG_E2E_SERVER_CMD`
- `OCG_E2E_SERVER_TIMEOUT`
- `OCG_E2E_REUSE_SERVER`
  Opt in to attaching to an already running app when `OCG_E2E_START_SERVER=true`

Database settings come from the usual `OCG_DB_*` variables and the e2e server
config. The default e2e test database name is configured by
`OCG_DB_NAME_TESTS_E2E`.

The e2e server uses `server-tests-e2e.yml` from `OCG_CONFIG` by default. This
config should point at the e2e database and listen on a different port from the
main local server, for example `127.0.0.1:9001` with base URL
`http://127.0.0.1:9001`.

When `OCG_DB_*` variables are not set, the email verification test reads DB
settings from `server-tests-e2e.yml`.

## Notes

- The committed e2e Node manifest lives at
  [`tests/e2e/package.json`](package.json).
- Keep [`tests/e2e/package-lock.json`](package-lock.json)
  committed and use `npm ci` so Playwright and its browser stack stay pinned for
  visual snapshots.
- Seeded e2e users use the password `Password123!` after
  `just db-load-tests-e2e-data`.
- Firefox and WebKit only run the smoke suite.

## Troubleshooting

- If navigation fails, verify the server is reachable at
  `<OCG_E2E_BASE_URL>/health-check`.
- If the database is missing seed data, rerun `just db-recreate-tests-e2e` and
  `just db-load-tests-e2e-data`.
- If port `9001` is busy, update `server-tests-e2e.yml` and run with a matching
  `OCG_E2E_BASE_URL`, for example
  `OCG_E2E_BASE_URL=http://localhost:9002 just e2e-tests`.

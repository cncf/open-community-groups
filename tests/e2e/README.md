# E2E Tests

End-to-end tests for Open Community Groups using Playwright.

## Prerequisites

- Node.js 22+
- PostgreSQL 17+ with `pgcrypto` and `postgis`
- Rust toolchain
- `tailwindcss` on `PATH`
- `tern` on `PATH`
- `just`

`just` installs Playwright and browsers, but it does not install `tailwindcss`
or `tern`.

## Quick Start

```bash
# Install e2e dependencies from tests/e2e/package.json
just e2e-install

# Recreate and migrate the main database
just db-recreate

# Load the e2e seed data into the main database
just db-load-e2e-data

# Start the server in another terminal
just server

# Run the Playwright suite
just e2e-tests
```

Locally this now follows the same shape as `gitjobs`: use the main database and
load the e2e seed data into it. CI still keeps its isolated e2e database flow
in [`.github/workflows/e2e.yml`](/Users/cintiasanchezgarcia/projects/open-community-groups/.github/workflows/e2e.yml).

## Common Commands

```bash
# Recreate and migrate the main database
just db-recreate

# Load the e2e seed data into the main database
just db-load-e2e-data

# Start the main server config
just server

# Run the full Playwright suite
just e2e-tests

# Update visual snapshots
just e2e-update-snapshots

# Run a specific Playwright project
cd tests/e2e && npx playwright test --config playwright.config.ts --project=chromium-smoke

# Open the Playwright UI
cd tests/e2e && npx playwright test --config playwright.config.ts --ui

# Run with a visible browser
cd tests/e2e && npx playwright test --config playwright.config.ts --headed
```

## Configuration

Most runs only need:

- `OCG_E2E_BASE_URL`
  Base URL used by Playwright. Default: `http://localhost:9000`

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

Database settings come from the usual `OCG_DB_*` variables. The default E2E
tests run against the main local database configured by `OCG_DB_NAME`.

When `OCG_DB_*` variables are not set, the email verification test also falls
back to the `db` section in `server.yml`.

## Notes

- The committed e2e Node manifest lives at
  [`tests/e2e/package.json`](/Users/cintiasanchezgarcia/projects/open-community-groups/tests/e2e/package.json).
- `npm install` may write `tests/e2e/package-lock.json`, which is ignored by git.
- Local e2e runs use the main app database and main server config, like `gitjobs`.
- Firefox and WebKit only run the smoke suite.

## Troubleshooting

- If navigation fails, verify the server is reachable at
  `<OCG_E2E_BASE_URL>/health-check`.
- If the database is missing seed data, follow the recreate/migrate/load steps
  from [`.github/workflows/e2e.yml`](/Users/cintiasanchezgarcia/projects/open-community-groups/.github/workflows/e2e.yml).
- If port `9000` is busy, run with
  `OCG_E2E_BASE_URL=http://localhost:9001 just e2e-tests`.

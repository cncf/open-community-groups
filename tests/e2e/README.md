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
# Install dependencies and Playwright browsers
just e2e-install

# Recreate the e2e database and load seed data
just e2e-db-setup

# Run the full e2e flow
just e2e-full
```

`just e2e-full`:
- Recreates the e2e database and loads seed data
- Writes a temporary server config
- Lets Playwright start the server
- Runs the E2E suite

## Common Commands

```bash
# Start the app with the generated e2e config
just e2e-server

# Run tests against an already running server
yarn test:e2e

# Debug in Playwright UI
yarn test:e2e:ui

# Run with a visible browser
yarn test:e2e:headed

# Run only smoke coverage
yarn test:e2e:smoke

# Run only the deeper Chromium suites
yarn test:e2e:deep

# Run visual regression checks
yarn test:e2e:visual

# Update visual snapshots
yarn test:e2e:visual:update
```

## Configuration

Most runs only need:

- `OCG_E2E_BASE_URL`
  Base URL used by Playwright. Default: `http://localhost:9000`
- `OCG_E2E_SERVER_BASE_URL`
  Base URL written into the generated server config. Default: `OCG_E2E_BASE_URL`
- `OCG_E2E_SERVER_ADDR`
  Listen address written into the generated server config. Default:
  `127.0.0.1:9000`

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

Database settings come from the usual `OCG_DB_*` variables, including
`OCG_DB_NAME_E2E` for the E2E database name.

## Notes

- `yarn test:e2e` runs the full Playwright config.
- Firefox and WebKit only run the smoke suite.
- Visual tests start the server automatically using the generated E2E config.

## Troubleshooting

- If navigation fails, use `just e2e-full` or verify the server is reachable at
  `<OCG_E2E_BASE_URL>/health-check`.
- If seeded pages or users are missing, rerun `just e2e-db-setup`.
- If port `9000` is busy, run with
  `OCG_E2E_BASE_URL=http://localhost:9001 just e2e-full`.

# E2E Tests

End-to-end tests for Open Community Groups using Playwright. These tests verify critical user journeys across the application by running tests against a real browser.

## Prerequisites

- Node.js 22+
- PostgreSQL 17+ with pgcrypto and postgis extensions
- Rust toolchain (for building the server)
- Tailwind CSS CLI available on `PATH`
- `tern` available on `PATH`
- Just task runner

## Setup

First-time setup:

```bash
# Install Playwright and dependencies
just e2e-install

# Setup e2e test database with test data
just e2e-db-setup
```

This will:
- Install Node.js dependencies (Playwright, TypeScript)
- Install Playwright browsers (Chromium, Firefox, WebKit)
- Create the `ocg_e2e` database
- Run all schema migrations
- Load test data (community, group, events)

The `just` tasks do not install `tailwindcss` or `tern`. The CI workflow installs
those tools explicitly before building the server and running migrations, and local
setups need them available on `PATH` as well.

## Running Tests

### Option 1: Full Automated Run (Recommended)

Run the complete e2e test suite with automatic server startup:

```bash
just e2e-full
```

This command:
- Sets up the e2e database
- Generates temporary server configuration
- Builds and starts the server
- Runs smoke coverage across all browsers and deeper coverage on Chromium
- Reports results

### Option 2: Manual (Two Terminals)

If you prefer to manage the server separately:

```bash
# Terminal 1: Start server with test config
just e2e-server

# Terminal 2: Run tests
just e2e-tests
```

### Option 3: Development/Debug Mode

For interactive testing and debugging:

```bash
# UI mode (recommended for development)
just e2e-tests-ui

# Headed mode (see browser in action)
just e2e-tests-headed

# Run specific browser only
yarn test:e2e:chromium
yarn test:e2e:firefox
yarn test:e2e:webkit

# Run only the fast cross-browser smoke suite
yarn test:e2e:smoke

# Run only the deeper Chromium suite
yarn test:e2e:deep

# Run visual regression checks for stable public pages
yarn test:e2e:visual

# Refresh visual baselines after intentional UI changes
yarn test:e2e:visual:update

# Refresh visual baselines with just
just e2e-tests-visual-update
```

## Test Structure

```
tests/e2e/
├── playwright.config.ts       # Playwright configuration
├── utils.ts                   # Helper functions and constants
├── pages/content/             # Public page rendering and browse flows
├── pages/flows/               # Stateful public page interactions
├── public/public.spec.ts      # Public pages suite
├── auth/auth.spec.ts          # Email/password authentication suite
├── auth/oauth.spec.ts         # OAuth redirect smoke tests
├── dashboard/access-control.spec.ts  # Dashboard auth gate checks
├── visual/visual.spec.ts      # Visual regression checks for stable pages
├── tsconfig.json              # TypeScript configuration
└── README.md                  # This file
```

## Test Data

Test data is defined in `/database/tests/data/e2e.sql` and includes:

- **Primary Community**: `e2e-test-community`
  - Display name: `E2E Test Community`
  - UUID: `11111111-1111-1111-1111-111111111111`

- **Secondary Community**: `e2e-second-community`
  - Display name: `E2E Second Community`
  - UUID: `11111111-1111-1111-1111-111111111112`

- **Primary Group**: `E2E Test Group Alpha`
  - Slug: `test-group-alpha`
  - UUID: `44444444-4444-4444-4444-444444444441`

- **Primary Event**: `Alpha Event One`
  - Slug: `alpha-event-1`
  - UUID: `55555555-5555-5555-5555-555555555501`

- Additional seeded data covers:
  - Multiple groups across both communities
  - Published, draft, canceled, past, and upcoming events
  - Community, group, member, viewer, and manager roles
  - CFS submissions, ratings, labels, invitations, sponsors, and sessions

## Test Coverage

### Suite Split

- `smoke`: `public/public.spec.ts`, `auth/oauth.spec.ts`, and `dashboard/access-control.spec.ts`
- `deep`: all remaining E2E specs, executed on desktop Chromium plus mobile-emulated Chromium
- `yarn test:e2e`: runs both suites together
- `yarn test:e2e:firefox` and `yarn test:e2e:webkit` run the smoke suite only

### Current Tests (Public Pages)

✅ Home page loads and displays correctly
✅ Explore page loads for events and groups
✅ Group page displays group information
✅ Event page displays event information
✅ Search returns matching groups
✅ Community and site home sections render seeded cards and stats
✅ Visual baselines for site, community, group, and event pages on desktop and mobile

### Visual Regression Tests

- `tests/e2e/visual/visual.spec.ts` snapshots stable public pages on desktop and mobile emulation
- Visual checks run on Chromium only as part of the deep suite to reduce noise
- `yarn test:e2e:visual` writes the e2e server config and starts the app automatically
- Update snapshots with `yarn test:e2e:visual:update` after intentional UI changes
- `just e2e-tests-visual-update` provides the same snapshot refresh flow through `just`
- Snapshot paths are shared across platforms to keep local and CI baseline names aligned

### Current Tests (Authentication)

✅ Email sign up requires verification before log in
✅ Seeded users can log in, log out, and keep redirect targets
✅ GitHub login redirects to authorization url
✅ Dashboard routes require login

### Current Tests (User Actions and Dashboards)

✅ Group membership join/leave flows
✅ Event attendance and attendee check-in flows
✅ Community dashboard list, search, team, and taxonomy coverage
✅ Group dashboard team, events, submissions, members, and sponsors coverage
✅ User dashboard invitations, events, proposals, and submissions coverage
✅ Public CFS entry points and proposal selection coverage

## Configuration

### Environment Variables

Configure test behavior via environment variables:

- `OCG_E2E_BASE_URL` - Base URL for tests (default: `http://localhost:9000`)
- `OCG_E2E_COMMUNITY_NAME` - Primary test community slug (default: `e2e-test-community`)
- `OCG_E2E_GROUP_SLUG` - Test group slug (default: `test-group-alpha`)
- `OCG_E2E_EVENT_SLUG` - Test event slug (default: `alpha-event-1`)
- `OCG_E2E_START_SERVER` - Auto-start server if not running (default: `false`)
- `OCG_E2E_SERVER_CMD` - Custom server start command
- `OCG_E2E_GITHUB_ENABLED` - Enable GitHub login in e2e config (default: `true`)
- `OCG_E2E_GITHUB_AUTH_URL` - GitHub auth url for redirects (default: `https://example.test/oauth/authorize`)
- `OCG_E2E_GITHUB_TOKEN_URL` - GitHub token url (default: `https://example.test/oauth/token`)
- `OCG_E2E_GITHUB_CLIENT_ID` - GitHub OAuth client id (default: `e2e-client`)
- `OCG_E2E_GITHUB_CLIENT_SECRET` - GitHub OAuth client secret (default: `e2e-secret`)
- `OCG_E2E_GITHUB_REDIRECT_URI` - GitHub OAuth redirect uri (default: `http://localhost:9000/log-in/oauth2/github/callback`)
- `OCG_E2E_LINUXFOUNDATION_ENABLED` - Enable Linux Foundation SSO link coverage (default: `true`)

### Database Configuration

E2E tests use a separate database (`ocg_e2e`) configured via justfile variables:

- `OCG_DB_HOST` - Database host (default: `localhost`)
- `OCG_DB_PORT` - Database port (default: `5432`)
- `OCG_DB_USER` - Database user (default: `postgres`)
- `OCG_DB_PASSWORD` - Database password (default: empty)
- `OCG_DB_NAME_E2E` - E2E database name (default: `ocg_e2e`)

## Routing Model

The E2E helpers target path-based community routes under the configured base URL.
For example, the seeded community and group pages are addressed like this:

```typescript
// Community home:
// http://localhost:9000/e2e-test-community

// Group page:
// http://localhost:9000/e2e-test-community/group/test-group-alpha
```

## Authentication Notes

Email/password tests require `login.email` enabled in the server config. The
`just e2e-write-server-config` task enables this by default.
GitHub redirect tests use dummy OAuth values by default and do not contact an
external provider.
Linux Foundation SSO smoke coverage only checks that the login link is visible
when the e2e config enables it. A reachable OIDC issuer is only needed for a
real redirect or callback flow.

## Troubleshooting

### Tests Fail with "Navigation Timeout"

**Cause**: Server not running or not accessible
**Solution**:
- Verify server is running: `curl http://localhost:9000/health-check`
- Check server logs for errors
- Use `just e2e-full` for automatic server management

### Tests Fail with "Community Not Found"

**Cause**: Test data not loaded or database needs refresh
**Solution**: Re-run database setup: `just e2e-db-setup`

### Browser Installation Fails

**Cause**: Missing system dependencies for Playwright browsers
**Solution**: Run with `--with-deps` flag: `yarn playwright install --with-deps`

### Port 9000 Already in Use

**Cause**: Another server instance is running
**Solution**:
- Stop other server: `pkill ocg-server`
- Or change port via `OCG_E2E_BASE_URL=http://localhost:9001`

### Search Test Fails

**Cause**: PostgreSQL full-text search configuration
**Solution**: The search test queries for "Test" which should match "E2E Test Group". If it fails, check that the `tsdoc` column is properly generated in the database.

## Best Practices

### Writing New Tests

1. **Use Role-Based Selectors**: Prefer `getByRole()` for accessibility and reliability
   ```typescript
   // Good
   page.getByRole("heading", { level: 1, name: "Title" })

   // Avoid
   page.locator("h1")
   ```

2. **Add Data Attributes**: For complex UI elements, add `data-*` attributes to templates
   ```html
   <!-- In template -->
   <button data-testid="join-group">Join Group</button>

   <!-- In test -->
   page.getByTestId("join-group")
   ```

3. **Use Helper Functions**: Keep navigation logic in `utils.ts`
   ```typescript
   // Good
   await navigateToGroup(page, "test-group");

   // Avoid
   await page.goto("/group/test-group");
   ```

4. **Handle Async Operations**: Wait for network requests and state changes
   ```typescript
   await page.waitForLoadState("networkidle");
   await expect(element).toBeVisible();
   ```

### Maintaining Test Data

- Keep test data minimal - only what's needed for current tests
- Use deterministic UUIDs for predictable test behavior
- Use future dates for events to avoid time-based flakiness
- Document any changes to test data in commit messages

## CI/CD Integration

E2E tests are designed to run in CI/CD pipelines. The planned GitHub Actions workflow will:

1. Setup PostgreSQL service
2. Create and migrate e2e database
3. Load test data
4. Build and start server
5. Run Playwright tests across all browsers
6. Upload test results as artifacts

*Note: CI/CD integration is not yet implemented.*

## Performance

- **Test Duration**: ~30 seconds for full suite (5 tests × 3 browsers)
- **Database Setup**: ~5 seconds
- **Server Startup**: ~10 seconds

## Resources

- [Playwright Documentation](https://playwright.dev/)
- [Playwright Best Practices](https://playwright.dev/docs/best-practices)
- [Open Community Groups Documentation](../../README.md)

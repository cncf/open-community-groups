# E2E Tests

End-to-end tests for Open Community Groups using Playwright. These tests verify critical user journeys across the application by running tests against a real browser.

## Prerequisites

- Node.js 22+
- PostgreSQL 17+ with pgcrypto and postgis extensions
- Rust toolchain (for building the server)
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
- Runs all Playwright tests across all browsers
- Reports results

### Option 2: Manual (Two Terminals)

If you prefer to manage the server separately:

```bash
# Terminal 1: Start server with test config
just e2e-write-server-config
cargo run -- -c /tmp/ocg-e2e.yml

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
```

## Test Structure

```
tests/e2e/
├── playwright.config.ts       # Playwright configuration
├── utils.ts                   # Helper functions and constants
├── public/public.spec.ts      # Public pages suite
├── auth/auth.spec.ts          # Email/password authentication suite
├── tsconfig.json              # TypeScript configuration
└── README.md                  # This file
```

## Test Data

Test data is defined in `/database/tests/data/e2e.sql` and includes:

- **Test Community**: `test-community.localhost`
  - Host-based routing for multi-tenant testing
  - UUID: `11111111-1111-1111-1111-111111111111`

- **Test Group**: "E2E Test Group"
  - Slug: `test-group`
  - Category: "E2E Category"
  - UUID: `44444444-4444-4444-4444-444444444444`

- **Test Events**:
  - Primary Event: "E2E Test Event" (slug: `test-event`)
  - Search Event: "E2E Search Event" (slug: `search-event`)
  - Both scheduled for future dates to avoid timing issues

## Test Coverage

### Current Tests (Public Pages)

✅ Home page loads and displays correctly
✅ Explore page loads for events and groups
✅ Group page displays group information
✅ Event page displays event information
✅ Search returns matching groups

### Current Tests (Authentication)

✅ Email sign up requires verification before log in

### Future Test Coverage

The following test scenarios are planned for future implementation:

- Authentication (login/logout with email)
- Group membership (join/leave groups)
- Event attendance (attend/cancel events)
- Organizer dashboard (manage groups and events)
- Form submissions (create groups, create events)
- Multi-browser compatibility edge cases

## Configuration

### Environment Variables

Configure test behavior via environment variables:

- `OCG_E2E_BASE_URL` - Base URL for tests (default: `http://localhost:9000`)
- `OCG_E2E_HOST` - Test community hostname (default: `test-community.localhost`)
- `OCG_E2E_USE_HOST_HEADER` - Force Host header override (default: `false`)
- `OCG_E2E_GROUP_SLUG` - Test group slug (default: `test-group`)
- `OCG_E2E_EVENT_SLUG` - Test event slug (default: `test-event`)
- `OCG_E2E_START_SERVER` - Auto-start server if not running (default: `false`)
- `OCG_E2E_SERVER_CMD` - Custom server start command

### Database Configuration

E2E tests use a separate database (`ocg_e2e`) configured via justfile variables:

- `OCG_DB_HOST` - Database host (default: `localhost`)
- `OCG_DB_PORT` - Database port (default: `5432`)
- `OCG_DB_USER` - Database user (default: `postgres`)
- `OCG_DB_PASSWORD` - Database password (default: empty)
- `OCG_DB_NAME_E2E` - E2E database name (default: `ocg_e2e`)

## Multi-Tenant Routing

OCG uses host-based routing for multi-tenancy. Tests handle this by:

1. **URL Rewriting**: When running against `localhost`, test helpers automatically rewrite URLs to use the test community hostname (`test-community.localhost`)
2. **DNS Configuration**: Browsers resolve `*.localhost` subdomains automatically without `/etc/hosts` configuration
3. **Server Routing**: The OCG server routes requests based on the `Host` header to the correct community

Example:
```typescript
// navigateToHome() automatically converts:
// http://localhost:9000/ → http://test-community.localhost:9000/
```

## Authentication Notes

Email/password tests require `login.email` enabled in the server config. The
`just e2e-write-server-config` task enables this by default.
Avoid `OCG_E2E_USE_HOST_HEADER` for auth flows because cookies are scoped to the
URL host, not the overridden `Host` header.

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

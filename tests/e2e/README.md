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

### Parallel Runs

`just e2e-tests` uses one worker because tests share the seeded database. To
run the chromium projects faster, give each worker a stack of its own:

```sh
just e2e-tests-parallel
OCG_E2E_PARALLEL_WORKERS=6 just e2e-tests-parallel
OCG_E2E_SERVER_BINARY=target/debug/ocg-server just e2e-tests-parallel \
  --project=chromium-deep site/common/not-found.spec.js
```

The recipe runs `scripts/parallel.sh`, which builds the server, then migrates
and seeds a template database (`ocg_tests_parallel_e2e` by default) once and
clones it per worker (`ocg_tests_parallel_N_e2e`). It starts one server per
worker on ports `9101` and up and runs Playwright with one worker per stack.
It does not touch the `just e2e-server` database or port. `stacks.js` binds
each worker to its stack through `OCG_E2E_STACKS`, and the preflight checks
every stack. The Firefox and WebKit smoke projects only run when selected
with `--project`. Playwright runs with `fullyParallel`, so the tests of one
file may run on different workers and stacks, in any order.

- Projects: without a `--project` argument the `chromium-deep` and
  `chromium-mobile-deep` projects run; any `--project` argument replaces that
  default.
- Prebuilt server: `OCG_E2E_SERVER_BINARY` names an executable to run instead
  of building one, absolute or relative to the repository root.
- Shutdown: after Playwright finishes or is interrupted, the servers are
  stopped with `SIGINT`, so they skip the drain delay and exit cleanly. The
  recipe exits with Playwright's status.
- Output: reports and artifacts go to the usual folders. Server logs
  (`server-N.log`), the run start on the database clock (`run-started-at`),
  the stack list (`stacks.json`) and the coverage reports (`route-hits.json`
  and `db-coverage.json`, see [Coverage Reports](#coverage-reports)) go to
  `$TMPDIR/ocg-e2e-parallel/`, which each run recreates.
  `OCG_E2E_RUN_ARCHIVE` names a folder that also keeps them, with the blob
  report and the run timing, for merging several runs (see [CI](#ci)).

The databases are kept after the run so a failure can be inspected. Each run
recreates them under the same names, so they do not pile up: there is the
template plus one per worker of the largest run. To drop one, for example:

```sh
OCG_E2E_DB_NAME=ocg_tests_parallel_1_e2e just db-drop-tests-e2e
```

Other useful commands:

```sh
# One spec file (path relative to tests/e2e), extra flags go to Playwright
just e2e-tests-file dashboard/common/session.spec.js --project=chromium-deep

# One project
just e2e-tests --project=chromium-deep

# Playwright UI / headed browser
just e2e-tests --ui
just e2e-tests --headed

# Write missing and rewrite mismatched ARIA snapshots (see ARIA Snapshots)
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

`OCG_E2E_BROWSER_HEALTH` sets what the `browserHealth` fixture does with
unexpected page errors and server 5xx responses: `enforce` (default) fails the
test, `report` only annotates it, as a local override while investigating. The
`reporters/diagnostics.js` reporter prints the `browser-health`,
`browser-health-allowed` and `navigation-retry` annotations of a run, grouped
by type, and appends them to `$GITHUB_STEP_SUMMARY` in CI. It never changes
the exit status.

`OCG_E2E_ROUTE_ATTRIBUTION=1` makes the fixtures record which test made each
server request (see [Route Attribution](#route-attribution)).

`OCG_E2E_JS_COVERAGE=1` makes the fixtures record the JS coverage of the
Chromium projects (see [JS Coverage](#js-coverage)).

Before the first test, `preflight.js` checks `/health-check` and compares a
marker written by `just e2e-db-reset` with the one the server renders. If
they differ, the server and psql point at different databases.

## Coverage Reports

Coverage reports show what a run reached, not what it asserted: a route hit,
a called function or a written audit row is not a check of its result. Only
complete runs give meaningful lists.

CI blocks on route and DB function coverage (see [CI](#ci)). A new route
needs an e2e hit or a [route coverage](#route-coverage) allowlist entry, and a
new `plpgsql` or trigger function needs an e2e call or a
[DB function](#db-functions-and-audit-actions) allowlist entry. Allowlist
entries name the Rust or pgTAP test that covers the route or function
instead.

### Route Hits

With `RUST_LOG` enabling `ocg_route_hits=debug`, the server logs one route-hit
event per response inside its request span, which carries the matched route
and the request ID. `parallel.sh` sets
`RUST_LOG=ocg_server=debug,ocg_route_hits=debug` unless `RUST_LOG` is already
set. After the servers stop, it writes
`$TMPDIR/ocg-e2e-parallel/route-hits.json` and prints its counts. To print the
full list of the last parallel run, or of other server logs:

```sh
just e2e-route-hits
just e2e-route-hits /tmp/ocg-e2e-server.log --json /tmp/route-hits.json
```

The report groups hits by method and matched route into `2xx`, `3xx`,
`3xx-log-in`, `4xx` and `5xx`, and lists every 5xx response with its request
ID. `3xx-log-in` holds the requests the log-in guard rejected, whatever their
status: HTMX and fetch requests get no 3xx. Requests no route matched count as
`fallback`. The recipe fails when the logs have no hits or only `fallback`
ones.

`just e2e-server` logs to the terminal, so a single-server run must save the
server output to a file and pass it to the recipe:

```sh
RUST_LOG=ocg_server=debug,ocg_route_hits=debug just e2e-server \
  >/tmp/ocg-e2e-server.log 2>&1
```

### Route Attribution

With `OCG_E2E_ROUTE_ATTRIBUTION=1`, the fixtures record which test made each
server request, and `--attribution` joins those records to the route hits on
the request ID:

```sh
OCG_E2E_ROUTE_ATTRIBUTION=1 just e2e-tests-parallel --project=chromium-deep \
  dashboard/group/sponsors
just e2e-route-hits --attribution tests/e2e/test-results/route-attribution
```

Every browser context a test uses, including contexts registered with
`browserHealth.track(context)`, appends one line per same-origin response
carrying `x-request-id` to `test-results/route-attribution/<worker>.jsonl`
(one file per worker, so appends never interleave): `requestId`, `testId`,
`file`, `title` and `phase`. The phase is `fixture` while authenticated page
fixtures and `pageAs` log in and prepare the page, and `test` afterwards,
hooks included. The report adds the hits per phase and the tests that hit each
route in the `test` phase, and flags routes never hit in that phase. With
`OCG_E2E_ROUTE_ATTRIBUTION=1`, `parallel.sh` joins the records into its
`route-hits.json`. `--attribution` takes several folders, so the logs and
records of several runs merge into one report.

Limits:

- Only browser requests are recorded. `page.request` calls (such as the
  dashboard context selection), the preflight and other requests made outside
  the browser count as `unattributed`.
- Route mocks without `x-request-id`, cross-origin requests and responses that
  arrive after their context closed are not recorded.
- Playwright empties `test-results` at the start of every run, so the records
  and the server logs must come from the same run.
- As with hits, a request made in the `test` phase is not an assertion.

### Route Coverage

`scripts/route-coverage.js` compares the route hits with
`coverage/route-manifest.json`. A route is covered by a hit below 400 that is
not a log-in redirect (`2xx` or `3xx`). Every other route needs an entry in
`coverage/route-coverage-allowlist.json` with its `method` and `path`, a
`reason`, a `note` explaining it and the test that covers the route instead
(`coveredBy`). Reasons:

- `disabled-in-e2e`: the e2e configuration does not mount the route (OAuth2
  and OIDC log-in).
- `provider-only`: the route needs a real response from an external provider
  such as Stripe.
- `untraced`: the route is served outside the trace layer, so it emits no
  route-hit event (`/static/{*file}`).
- `non-2xx-by-design`: the route answers 4xx or 5xx by design in e2e. The
  entry also explains the 5xx responses of a covered route.
- `rust-only` and `pgtap-only`: e2e cannot reach the route, or reaching it
  would only repeat a handler or SQL branch, so a Rust or pgTAP test
  covers it.

`coveredBy` is `e2e:<spec>` (relative to `tests/e2e`), `pgtap:<path>`
(relative to the repository root), `rust:<test function>` or, for test names
several modules share, `rust:<file>::<test function>`.

After the servers stop, `parallel.sh` prints the summary. To print the full
lists for the last parallel run, or to fail like a blocking check:

```sh
just e2e-route-coverage
just e2e-route-coverage --blocking
just e2e-route-coverage --route-hits /tmp/route-hits.json --json /tmp/route-coverage.json
```

`--blocking` fails on uncovered routes without an entry and on allowlist
errors: entries not in the manifest, duplicates and `coveredBy` values that
name no existing test. The check also warns, without failing, on allowlisted
routes the run covered, on 5xx hits of routes without a `non-2xx-by-design`
entry and on hit routes missing from the manifest. Only a complete run gives
a meaningful uncovered list; partial runs leave most routes uncovered.

### DB Functions and Audit Actions

`just e2e-db-reset` and every parallel stack set `track_functions = 'all'` on
the e2e database, so PostgreSQL counts calls per function. Setting it needs a
superuser; without one the recipes warn and the report has no data. Calls made
by test helpers through `psql` count too.

After the servers stop, `parallel.sh` writes
`$TMPDIR/ocg-e2e-parallel/db-coverage.json` and prints its counts. To print the
full lists of the last parallel run:

```sh
just e2e-db-coverage
# Single-server run: stop just e2e-server first, then read its database
just e2e-db-coverage --db ocg_tests_e2e
# Sum the reports of several runs, such as CI shards (absolute paths)
just e2e-db-coverage --merge /tmp/e2e-runs/functional-1/db-coverage.json \
  --merge /tmp/e2e-runs/functional-2/db-coverage.json
# Fail like the blocking check
just e2e-db-coverage --blocking
```

`--blocking` fails on uncalled `plpgsql` and trigger functions without an
entry and on allowlist errors. Allowlist warnings never fail.

The report sums the stacks (or the merged runs) and lists:

- Uncalled `plpgsql` and trigger functions without an entry in
  `coverage/db-function-allowlist.json`. Each entry gives the function, a
  reason and the test that covers it instead (`coveredBy`:
  `pgtap:<path>` or `rust:<test function>`, with the same forms as the
  route coverage allowlist). Add `"intermittent": true` when worker timing
  decides whether a run calls the function, such as a worker step that races
  the test cleanup or the server shutdown.
- Uncalled `sql` functions, informational only: the planner may inline them,
  so they are never counted.
- Allowlist errors: entries naming no public function or an `sql` one,
  duplicates and `coveredBy` values that name no existing test.
- Allowlist warnings: entries of functions the run called, unless the entry
  is `intermittent`.
- Audit actions written since `run-started-at` (a time filter, so no rows are
  deleted) compared with the actions the functions in
  `database/migrations/functions` can write. A single-server run counts every
  row, seed included, unless `--since` is given.

### JS Coverage

With `OCG_E2E_JS_COVERAGE=1`, every Chromium context a test uses (the same
contexts as route attribution) records the V8 coverage of its pages from
before their first navigation. Closing a page or its context through
`page.close()` or `context.close()` stops it, and each worker merges the
coverage of the scripts under `/static/js/` and writes it to
`test-results/js-coverage/raw/e2e-<worker>.json` when it exits. Firefox and
WebKit pages are not recorded. The unit tests write the same raw format to
`tests/unit/coverage/raw/` when run with `--coverage`, next to their lcov
report.

`scripts/js-coverage-report.js` merges both with
[monocart](https://github.com/cenfun/monocart-coverage-reports). It maps each
served script back to its file in `ocg-server/static/js` (the content hash is
stripped from e2e paths, and the import specifiers the servers rewrite are
aligned with the source), writes `e2e/`, `unit/` and `merged/` HTML reports
and `js-coverage-matrix.json` to `coverage-reports/js-coverage/`, and prints
which suites ran each module: `both`, `e2e-only`, `unit-only` or `neither`,
with their line coverage. Scripts served from other sources than the checkout
(a stale server build) are skipped and counted.

```sh
OCG_E2E_JS_COVERAGE=1 just e2e-tests-parallel --project=chromium-deep site/event
# Unit tests with coverage, then the report (extra arguments go to the script)
just e2e-js-coverage
just e2e-js-coverage --summary
# Report only, from the raw folders of several runs, such as CI shards
node tests/e2e/scripts/js-coverage-report.js \
  --e2e /tmp/e2e-runs/functional-1/js-coverage \
  --e2e /tmp/e2e-runs/functional-2/js-coverage
```

Loading a module runs its top-level code, so a module counts as run by a
suite as soon as the suite loads it; the line coverage tells how much of it
ran.

### Rust Coverage

`just e2e-rust-coverage` measures which server handler and service lines the
e2e suite reaches compared with `cargo test`. It runs on demand only, never in
CI, and needs [cargo-llvm-cov](https://github.com/taiki-e/cargo-llvm-cov) and
the `llvm-tools-preview` rustup component. The recipe loads
`cargo llvm-cov show-env`, builds an instrumented server in
`target/llvm-cov-target` (the regular build is left alone), runs the chromium
suite with `--update-snapshots=none`, so it never writes ARIA snapshots, through
`just e2e-tests-parallel` (stopping the servers with SIGINT writes their
profiles) and exports `target/llvm-cov/e2e.lcov`. It then
runs `cargo test -p ocg-server` into `target/llvm-cov/unit.lcov`.
`scripts/rust-coverage-diff.js` compares both and writes
`target/llvm-cov/e2e-vs-unit.md`: the totals per area, then the lines of
`ocg-server/src/handlers` and `ocg-server/src/services` hit only by
`cargo test` or by neither, per file. Only lines the server binary
instruments count, so test-only code is left out. With `CARGO_TARGET_DIR`
set, both folders are created under it instead of `target`.

```sh
cargo install --locked cargo-llvm-cov
rustup component add llvm-tools-preview
# Extra arguments go to Playwright; the coverage of a failed run is partial
just e2e-rust-coverage
just e2e-rust-coverage site/event
# Compare two lcov files again
node tests/e2e/scripts/rust-coverage-diff.js --e2e /tmp/e2e.lcov \
  --unit /tmp/unit.lcov --out /tmp/e2e-vs-unit.md
```

The instrumented build compiles the dependencies again into its own target
dir, so the first run is slow.

## Projects

- `chromium-deep`: every desktop test on Chromium.
- `chromium-mobile-deep`: tests tagged `@mobile` on a mobile device.
- `firefox-smoke`, `webkit-smoke`: desktop tests tagged `@smoke` on Firefox
  and WebKit (see Writing Tests).

ARIA snapshot tests are regular tests of the chromium projects (see
[ARIA Snapshots](#aria-snapshots)).

CI runs these projects on isolated stacks (see [CI](#ci)).

### ARIA Snapshots

ARIA snapshots (`toMatchAriaSnapshot`) record the accessibility tree of one
page region as YAML: roles, accessible names, text, states and link targets.
Together with the layout checks of `expectPageLayout` they replace pixel
screenshots, so they give the same result on every OS and need no
CI-rendered baselines.

- They catch: missing, renamed or reordered regions, headings, links,
  buttons and form fields, changed copy and wrong link targets. Added
  nodes, such as elements shown at the wrong viewport, fail only in files
  that start with `- /children: deep-equal` (see Conventions); Playwright
  otherwise matches in contain mode, where the file only has to appear as an
  ordered subsequence of the tree. `expectPageLayout` adds horizontal
  overflow, key regions leaving the viewport and a stylesheet that does not
  apply.
- They do not catch styling: colour, spacing, font, size and alignment
  changes pass unnoticed. Review those changes in a browser.
- Files: `toMatchAriaSnapshot({ name })` reads `<name>.aria.yml` from the
  `<spec>-snapshots/` folder next to the spec
  (`expect.toMatchAriaSnapshot.pathTemplate` in `playwright.config.js`).
  Files are used instead of inline templates so specs stay short, each
  region is reviewed as a text diff of its own, and an update rewrites only
  the files that no longer match, keeping the regexes of the others.
- Helpers (`snapshots.js`): `expectAriaSnapshot(page, region, name)` waits
  for HTMX and the event attendance controls to settle, then matches the
  region. `expectPageLayout(page, { regions })` checks that the stylesheet
  applies (a computed-style check on the skip link), that the document is no
  wider than the viewport, and that each region is visible and horizontally
  inside the viewport. `navigateToPath` already fails when the stylesheet
  loads empty or with an error status. `enableDesktopVersion(page)` sets
  the cookie of the user menu's "Desktop version" item on the page's
  context, so later pages lay out at 1280px on mobile.

Updating, on any OS (it starts its own isolated stacks):

```sh
# Every aria.spec.js; missing files are written, mismatched ones rewritten
just e2e-update-snapshots
# Some specs or folders; Playwright flags in --flag=value form
just e2e-update-snapshots site/event --project=chromium-deep
```

A run without `--update-snapshots` also writes a missing file, but fails
the test, so CI never passes on a snapshot it has not compared.

Review the changed files with `git diff -- '*.aria.yml'` like code: every
changed line should follow from the change under review. Playwright writes
numbers of two or more digits as `\d+`, but single digits, month names and
hand-written regexes come out literally, and the `/children` line is
dropped, so restore the regexes and the `/children` line an update replaced
(for example with `git checkout -p`), then run the specs again with the
repeat rule.

Conventions, for public pages and dashboard tabs alike:

- Each page or dashboard tab keeps its snapshots in an `aria.spec.js` in its
  own folder (`site/<page>/`, `dashboard/<scope>/<tab>/`), with a desktop
  test and a `@mobile` test that open the page the same way and call
  `expectPageLayout` with the regions they snapshot.
  `site/common/aria.spec.js` covers the layout, header and footer of every
  `PUBLIC_PAGES` row at both viewports; shared dashboard chrome (header,
  menu) belongs in `dashboard/<scope>/common/aria.spec.js`.
- Dashboard tabs that show the mobile notice instead of their content run
  their `@mobile` test in the desktop version (`enableDesktopVersion`),
  matching the desktop files. The scope's `common/aria.spec.js` captures the
  notice and checks every tab's mobile layout once. A tab's views (filters,
  dialogs, add and update forms, nested tabs) are `test.step`s of those two
  tests; a tab with many views may split them into several desktop and
  `@mobile` pairs, one per group of views (`dashboard/group/events/`).
- Snapshot 2 to 4 meaningful regions per page, and 1 to 3 per dashboard
  view, found by role and name (`getByRole("region", { name })`, forms,
  navigation, tables): the navigation, the page summary, forms, toolbars,
  table headers and the rows or cards of seeded read-only entities.
- Name a file after its page and region (`group-summary`). Add `-desktop`
  and `-mobile` only when the mobile tree differs (responsive elements
  hidden or replaced); otherwise both tests match the same file.
- Public page files start with `- /children: deep-equal`, so the region's
  tree must match the file exactly and an element added or leaked to the
  wrong viewport fails. Leave it out only for a partial template, and say
  why in the spec (`site/docs/aria.spec.js` leaves out the docs content).
- Leave out what other tests change: rows they add to seeded groups,
  communities or events (event, group, member and attendee lists, explore
  results), counts, and dates or relative times. When a region cannot avoid
  a dynamic value, match it with a regex in the file, such as
  `- text: /\d+ members? [A-Z][a-z]+ \d{4}/`; quote the value when it
  contains a colon followed by a space.
- Snapshot pages as the user who sees them; authenticated tabs use the
  role's page fixture, and an owned row the test creates may be snapshotted
  when the test owns and removes it.
- Group dashboard tabs open a temporary group the test owns, with the first
  organizer as admin (`setupAriaGroup` in `dashboard/group/aria-helpers.js`),
  so each list holds only the rows the test adds. Community dashboard tabs
  do the same with a temporary community and the first admin
  (`setupAriaCommunity` in `dashboard/community/aria-helpers.js`). Match the
  generated group, category and community names and slugs, and the IDs in
  links, with regexes.
- Markdown editors expose their text area only in the desktop layout, so
  leave that bare `- textbox` child of `- application` out of the file.

## CI

`.github/workflows/e2e.yml` builds the server once, and every test job runs
`just e2e-tests-parallel` with that binary on fresh isolated stacks:

- `functional`: three shards of `chromium-deep` and `chromium-mobile-deep`
  (`--shard=N/3`), ARIA snapshots included, with six workers each and
  `OCG_E2E_ROUTE_ATTRIBUTION=1`.
- `smoke` (Smoke (Firefox and WebKit)): the `firefox-smoke` and
  `webkit-smoke` projects with two workers.
- `repeat-changed-specs`: the repeat rule on pull requests (see below).
- `merge-reports`: runs whenever a test job ran, failed shards included. It
  merges the blob reports into one HTML and JSON report (the
  `playwright-report-merged` artifact) and adds the totals, run durations,
  failed tests, diagnostics counts, and the route hits, route coverage and DB
  coverage of all runs to the step summary, and uploads the coverage reports
  as `coverage-reports`. When `functional` and `smoke` both
  succeeded, it then runs the route and DB function coverage checks with
  `--blocking` on the merged reports. A failed test job skips the checks:
  its runs are partial, and the job is already red.

Each test run sets `OCG_E2E_RUN_ARCHIVE`, so `parallel.sh` also keeps the
run's files in a folder named after the run (`functional-N`, `smoke`): the
blob report (`blob/`), the server logs, `route-hits.json`,
`db-coverage.json`, the route attribution records, the raw JS coverage
(`js-coverage/`, with `OCG_E2E_JS_COVERAGE=1`) and `run.json` with the
duration and exit status. The jobs upload these folders as `e2e-run-*`
artifacts. The blob reports carry the traces and screenshots of failed tests,
so the merged HTML report shows them; videos are off.

The `stack_workers` and `repeat_each` dispatch inputs change the functional
shards for flake measurements. The `js_coverage` input sets
`OCG_E2E_JS_COVERAGE=1` on the functional shards; `merge-reports` then runs
the unit tests with coverage and adds the [JS coverage](#js-coverage) report
of all shards to the step summary and to `coverage-reports` (`js-coverage/`).

To reproduce a functional shard, and to merge archived runs the way
`merge-reports` does (`CI=1` selects the blob reporter):

```sh
CI=1 OCG_E2E_PARALLEL_WORKERS=6 OCG_E2E_ROUTE_ATTRIBUTION=1 \
  OCG_E2E_RUN_ARCHIVE=/tmp/e2e-runs/functional-1 \
  just e2e-tests-parallel --shard=1/3
cd tests/e2e
rm -rf blob-report && mkdir blob-report && cp /tmp/e2e-runs/*/blob/*.zip blob-report/
npx playwright merge-reports --config merge.config.js blob-report
node scripts/report-summary.js --json merged-report/results.json --runs-dir /tmp/e2e-runs
scripts/coverage-reports.sh /tmp/e2e-runs /tmp/coverage-reports
node scripts/route-coverage.js --summary --blocking \
  --route-hits /tmp/coverage-reports/route-hits.json
node scripts/db-coverage.js --summary --blocking \
  --merge /tmp/coverage-reports/db-coverage.json
```

On pull requests, CI enforces the repeat rule (see Writing Tests) on
changed specs. `scripts/changed-specs.js` selects the changed specs plus the
specs importing a changed spec-local helper (`helpers.js`, `*-helpers.js`;
shared root modules such as `utils.js` do not expand) and the specs whose
ARIA snapshot files changed, and splits them into at
most eight chunks. Each chunk runs on one isolated stack with one worker, so
every repetition of a file shares its database. To reproduce a chunk:

```sh
node tests/e2e/scripts/changed-specs.js '["tests/e2e/dashboard/group/events/helpers.js"]'
OCG_E2E_PARALLEL_WORKERS=1 just e2e-tests-parallel --project=chromium-deep \
  --project=chromium-mobile-deep --repeat-each=3 --retries=0 <specs>
```

## Writing Tests

### Where a Test Goes

Take the first rule that matches:

1. A pure SQL or handler branch (a validation, an error mapping, a
   permission edge) goes to a pgTAP or Rust test, not to e2e. E2E tests
   cover the seams between the browser, the server and the database.
2. ARIA snapshots and layout checks of a page or tab go to `aria.spec.js`
   in its folder (rules 4 and 5, see [ARIA Snapshots](#aria-snapshots)).
3. A flow across two or more roles or surfaces goes to `workflows/`.
4. One dashboard tab goes to `dashboard/<scope>/<tab>/`. Contracts shared by
   every dashboard (permissions, tables, session, context) go to
   `dashboard/common/`; navigation shared by the tabs of one scope goes to
   `dashboard/<scope>/common/`.
5. One public page goes to `site/<page>/`, and contracts shared by public
   pages go to `site/common/`. A new public page also gets a `PUBLIC_PAGES`
   row in `site/common/public-pages.js`, so the landmark, alt-text,
   responsive and axe checks cover it.

Existing specs move only when a new home is created for them or when they are
rewritten.

### Helpers and Data Graphs

- Shared helpers: `utils.js` (navigation, `uniqueName`, `futureDate`),
  `seed.js` (seeded IDs and credentials), `database.js` (psql queries),
  `snapshots.js` (ARIA snapshots, layout checks and page settling),
  `notifications.js`, `webhooks.js`, `data-graphs/` (disposable data graphs) and
  per-folder `helpers.js`.
- SQL that sets up, resets or cleans up test data is built in a
  `data-graphs/` module, not in specs or folder helpers. Values are quoted
  with `sqlString`, `sqlUuid`, `sqlTextArray` and `sqlUuidArray` from
  `database.js`. A read-only probe used by a single spec (a count, a status
  lookup) may stay in that spec.
- `insertOwnedEvent` (`data-graphs/events.js`) is the only `insert into event`:
  one transaction writes the event, its ticket tiers (free unless a tier sets
  `amountMinor`, which also needs `paymentCurrencyCode`), organizers,
  attendees, waitlist and speakers. Data graphs that need an event wrap it, and
  tests create one with `owned.event(opts)`.
- The `owned` fixture (`fixtures.js`) registers cleanups for owned data:
  `owned.defer(fn)` and `owned.track(value, cleanup)`, plus builders such as
  `owned.event(opts)`, `owned.cohostEvent(opts)` and `owned.attendee(opts)`.
  Cleanups run last in, first out after the test, keep going when one fails
  and report every failure. Page-driven cleanups stay in `finally`, since page
  fixtures may be closed by then.

### Data Ownership and Isolation

- Seeded rows are read-only. A test that mutates data owns the rows it creates
  or changes and restores them by ID in `finally` or `owned` teardown, so any
  spec passes with `--repeat-each=5 --retries=0` without reseeding. CI repeats
  changed specs three times on pull requests.
- Tests in one file may run on different stacks and in any order, so a test
  never relies on rows or state left by another test. A file that cannot avoid
  it opts out with `test.describe.configure({ mode: "default" })` and a
  comment naming the shared state.
- Plain-column seeded rows (`community`, `community_team`, `group`,
  `group_sponsor`, `group_team`, `user`) are restored with
  `withRowRestore({ table, key }, fn)` from `database.js`, which snapshots the
  row and writes it back after `fn`, even when `fn` throws. A seeded `event`
  row saved through the editor is restored the same way; its sessions and
  ticketing are not. Lifecycle tables (attendees, offers, purchases) use
  targeted SQL resets instead.
- Rows created through the browser use `uniqueName()` and `futureDate()`;
  do not use `Date.now()` or fixed future years such as `2030-`.
- Month-relative assertions use `getSeedClock(eventId).monthStart` from
  `database.js` (pass `TEST_CALENDAR_EVENTS.thisMonth.id`), not `new Date()`,
  so a run that crosses a month boundary after seeding keeps passing.
  Webhook timestamps use `nowInSeconds()` from `webhooks.js`.
- Seeded scheduled events start at 10:00 in their timezone on a date
  relative to the seed day, such as
  `date_trunc('day', now()) + interval '10 days 10 hours'`, so a single-day
  event never crosses midnight whatever time the stacks are seeded. Only live
  and starting-soon fixtures stay relative to `now()`.
- Notifications go through the automatic `notifications` fixture. It snapshots
  the `notification` table before the test and its hooks, and deletes every
  row created since then at teardown, with the template data and attachments
  left unreferenced and every `custom_notification` row created since the
  snapshot. Assert the new rows by kind and recipient with
  `notifications.expectNew(expectations)`, using
  `{ since: notifications.checkpoint() }` for a later window. The
  time-window delete relies on one worker per database, which both runners
  enforce. Email delivery is not asserted.
- Stripe and Zoom are covered through signed webhooks only; flows that need the
  real providers (for example `checkout.session.completed`) are out of scope.

### Pages, Waits and Timeouts

- Role-parameterized tests (tables, permission matrices, redirect loops) take
  the `pageAs` fixture: `await pageAs("organizerGroupPage")` opens that
  authenticated page fixture by name, reusing its cached session, and closes
  it after the test. Only use it for cases that differ by fixture, not by
  body. A cache miss logs in inside the test, so the login counts against the
  test timeout.
- The automatic `browserHealth` fixture watches every browser context a test
  uses through fixtures (`context`, `page`, authenticated page fixtures and
  `pageAs`) for uncaught page errors (`weberror`) and same-origin responses
  with status 500 or above that carry `x-request-id`, so fulfilled route mocks
  are ignored. Contexts from `browser.newContext()` need
  `browserHealth.track(context)`; `page.request` calls are never seen, so
  assert their status explicitly. Expected violations are allowed per test
  with `browserHealth.allow({ kind, pattern, reason })`, where `kind` is
  `page-error` or `server-error`, `pattern` is a substring or RegExp of the
  reported message (for server errors `<status> <method> <path>`, without the
  request id) and `reason` says why it is expected. Repeats of one violation
  are merged into one note with their count. Any violation that is not
  allowed fails the test (see `OCG_E2E_BROWSER_HEALTH`).
- Response waits use the `utils.js` matchers instead of raw
  `page.waitForResponse`: `waitForActionResponse` (one response, then HTMX
  settles; `settle: false` when the action navigates),
  `waitForActionResponses` (several responses from one action) and
  `waitForResponseMatching` (arm, act in steps, then await). Match on
  `method` plus `pathname` and `params` and pin the exact `status` (a number
  or an array of the allowed ones).
- SweetAlert dialogs use `confirmAlert` (checks the message and confirms,
  inside the action when it sends a request), `dismissAlert` (checks the
  message and closes) and `dismissAlertIfPresent` only for optional prompts.
- Worker-owned transitions (payments, badges) are awaited with `expect.poll`
  and include the job row status in the failure message.
- Tests fit the default 30 s timeout. A `test.setTimeout` or
  `test.describe.configure({ timeout })` override needs a one-line comment
  giving the reason, such as an `expect.poll` budget beyond the default, and
  review rejects overrides without one. Move slow setup into a data graph
  instead of raising the budget.

### Tags and Accessibility

- The `@smoke` tag (appended to the title) also runs a desktop test on
  Firefox and WebKit. Tag only flows that are repeat-safe and
  engine-sensitive (forms, menus, HTMX swaps, modals, navigation), keep the
  set small, and never tag `@mobile` tests. Run tagged tests
  with `--project=firefox-smoke --project=webkit-smoke --repeat-each=2
  --retries=0` before tagging.
- Accessibility scans use `expectNoAxeViolations(page, { scan, exclude })`
  from `axe.js` once the page is ready and HTMX has settled
  (`site/common/axe.spec.js` scans every `PUBLIC_PAGES` row and
  `dashboard/common/axe.spec.js` representative dashboard tabs). It runs the
  WCAG 2.0 and 2.1 A and AA rules except `color-contrast` and fails on
  critical and serious violations only. Fix the markup when the fix does not
  change pixels. Otherwise add an `axe-allowlist.js` entry
  (`{ scan, rule, target?, reason }`, where `target` is a CSS selector the
  node matches or sits inside) or pass an `exclude` selector with a comment
  giving the reason. A scan also fails when one of its allowlist entries no
  longer matches, so remove entries once the markup is fixed.

## Troubleshooting

- Preflight failure: run `just e2e-db-reset`, restart `just e2e-server` and
  make sure both use the same `OCG_E2E_*` values.
- Navigation errors: check `<OCG_E2E_BASE_URL>/health-check` responds.
  `navigateToPath` retries only connection failures (refused or reset, up to
  3 attempts; each retry is recorded as a `navigation-retry` annotation). Goto
  timeouts, missing responses and missing assets fail at once; the asset error
  names the stylesheet or HTMX script that did not load.
  `logInWithSeededUser` submits once and fails with "Login rejected" when
  `POST /log-in` redirects back to the login page.
- Port `9001` busy: start the server with `OCG_SERVER__ADDR=127.0.0.1:9002`
  and set `OCG_E2E_BASE_URL` to match.
- `OCG_E2E_START_SERVER=true` lets Playwright start the server itself
  (`OCG_E2E_SERVER_CMD`, `OCG_E2E_SERVER_TIMEOUT`, `OCG_E2E_REUSE_SERVER`).
- Keep `package-lock.json` committed and use `npm ci` so browser versions stay
  pinned; a new Chromium can change the accessibility tree ARIA snapshots
  record.

import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { test as base, expect } from "@playwright/test";

import { cleanupOwnedAttendee, setupOwnedAttendee } from "./data-graphs/attendance.js";
import { cleanupSessionProposals, readSessionProposalId, setupSessionProposal } from "./data-graphs/cfs.js";
import { cleanupCohostEvents, setupCohostEvent } from "./data-graphs/cohosts.js";
import { cleanupEventsByIds, insertOwnedEvent } from "./data-graphs/events.js";
import {
  deleteNotificationsCreatedSince,
  expectNewNotifications,
  listNotificationsSince,
  snapshotNotifications,
} from "./notifications.js";
import { TEST_COMMUNITY_IDS, TEST_GROUP_IDS, TEST_USER_CREDENTIALS } from "./seed.js";
import { buildE2eUrl, logInWithSeededUser, selectCommunityContext, selectGroupContext } from "./utils.js";

// Authenticated page fixtures: seeded credentials plus the dashboard context they select.
const AUTHENTICATED_PAGE_FIXTURES = {
  adminCommunityPage: {
    credentials: TEST_USER_CREDENTIALS.admin1,
    preparePage: (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.community1),
  },
  adminEmptyCommunityPage: {
    credentials: TEST_USER_CREDENTIALS.admin1,
    preparePage: (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.empty),
  },
  adminSecondaryCommunityPage: {
    credentials: TEST_USER_CREDENTIALS.admin2,
    preparePage: (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.community2),
  },
  checkInManagerGroupPage: {
    credentials: TEST_USER_CREDENTIALS.checkInManager1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.alpha),
  },
  communityViewerPage: {
    credentials: TEST_USER_CREDENTIALS.communityViewer1,
    preparePage: (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.community1),
  },
  emptyUserPage: { credentials: TEST_USER_CREDENTIALS.empty },
  eventsManagerGroupPage: {
    credentials: TEST_USER_CREDENTIALS.eventsManager1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.alpha),
  },
  groupViewerPage: {
    credentials: TEST_USER_CREDENTIALS.groupViewer1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.alpha),
  },
  groupsManagerPage: {
    credentials: TEST_USER_CREDENTIALS.groupsManager1,
    preparePage: (page) => selectCommunityContext(page, TEST_COMMUNITY_IDS.community1),
  },
  member1Page: { credentials: TEST_USER_CREDENTIALS.member1 },
  member2Page: { credentials: TEST_USER_CREDENTIALS.member2 },
  organizerEmptyGroupPage: {
    credentials: TEST_USER_CREDENTIALS.organizer1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.empty),
  },
  organizerExternalGroupPage: {
    credentials: TEST_USER_CREDENTIALS.organizer1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.externalPayments),
  },
  organizerGroupPage: {
    credentials: TEST_USER_CREDENTIALS.organizer1,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community1, TEST_GROUP_IDS.community1.alpha),
  },
  organizerGroupWithoutPaymentsPage: {
    credentials: TEST_USER_CREDENTIALS.organizer2,
    preparePage: (page) =>
      selectGroupContext(page, TEST_COMMUNITY_IDS.community2, TEST_GROUP_IDS.community2.delta),
  },
  pending1Page: { credentials: TEST_USER_CREDENTIALS.pending1 },
  pending2Page: { credentials: TEST_USER_CREDENTIALS.pending2 },
};

// Violation kinds `browserHealth` records: uncaught page errors and real server 5xx responses.
const BROWSER_HEALTH_KINDS = ["page-error", "server-error"];

// `enforce` fails the test on browser health violations; `report` (a local override) only annotates them.
const BROWSER_HEALTH_MODE = process.env.OCG_E2E_BROWSER_HEALTH || "enforce";

if (!["enforce", "report"].includes(BROWSER_HEALTH_MODE)) {
  throw new Error(`OCG_E2E_BROWSER_HEALTH must be "report" or "enforce" (got "${BROWSER_HEALTH_MODE}")`);
}

// Server build output the e2e server serves `/static/` from, read for script sources Playwright omitted.
const JS_COVERAGE_DIST_DIR = fileURLToPath(new URL("../../ocg-server/dist", import.meta.url));

// Whether tracked Chromium contexts record the V8 JS coverage of the app modules (see README "JS coverage").
const JS_COVERAGE_ENABLED = process.env.OCG_E2E_JS_COVERAGE === "1";

// URL path prefix of the app modules whose JS coverage is kept (vendor scripts live elsewhere).
const JS_COVERAGE_PATH_PREFIX = "/static/js/";

// Request ids listed per merged server error note, so repeats stay findable in the server logs.
const MAX_LISTED_REQUEST_IDS = 3;

// Whether tracked contexts record which test made each server request (see README "Route attribution").
const ROUTE_ATTRIBUTION_ENABLED = process.env.OCG_E2E_ROUTE_ATTRIBUTION === "1";

// Browser health monitors by test, created by whichever of the fixture or a tracked context comes first.
const browserHealthMonitors = new WeakMap();

// JS coverage of this worker, merged per script path and written by the `jsCoverage` worker fixture.
const jsCoverageByPath = new Map();

// Contexts whose pages record JS coverage.
const jsCoverageContexts = new WeakSet();

// JS coverage start of each page, resolving to whether it started; removed when coverage stops.
const jsCoverageStarts = new WeakMap();

// Chain of pending merges into `jsCoverageByPath`, so page stops never merge concurrently.
let jsCoverageMerges = Promise.resolve();

// Route attribution phase of each tracked context: `fixture` while logging in and preparing a page, then `test`.
const routeAttributionPhases = new WeakMap();

// Storage state is cached per fixture name so fixtures sharing a user never share a context.
const storageStateCache = new Map();

/** Builds a reusable page fixture for an authenticated seeded user. */
const authenticatedPageFixture = (fixtureName, { credentials, preparePage }) => {
  // Depends on `browserHealth` so the monitor outlives the page and sees it until it closes.
  return async ({ browser, browserHealth: _browserHealth }, use) => {
    const preparedPage = await createPreparedPage(browser, fixtureName, credentials, preparePage);

    try {
      await use(preparedPage.page);
    } finally {
      await preparedPage.close();
    }
  };
};

/**
 * Watches every context the test tracks (see `trackContext`) for uncaught page errors and real
 * server 5xx responses, and reports them at teardown according to `OCG_E2E_BROWSER_HEALTH`.
 * Exposes `track(context)`, which runs `trackContext`, for contexts created with
 * `browser.newContext()` and `allow({ kind, pattern, reason })` for expected violations: `kind`
 * is `page-error` or `server-error`, `pattern` a substring or RegExp matched against the
 * violation message (for server errors `<status> <method> <path>`, without the request id).
 */
const browserHealthFixture = async ({}, use, testInfo) => {
  const monitor = getBrowserHealthMonitor(testInfo);

  await use({ allow: monitor.allow, track: (context) => trackContext(context, testInfo) });

  reportBrowserHealth(monitor, testInfo);
};

/** Overrides Playwright's `context` fixture so it, and the default `page`, go through `trackContext`. */
const contextFixture = async ({ browserHealth: _browserHealth, context }, use, testInfo) => {
  trackContext(context, testInfo);
  await use(context);
};

/**
 * Creates the browser health state of one test. Tracked contexts record `weberror` events and
 * same-origin responses >= 500 carrying `x-request-id`, so fulfilled route mocks (no request id)
 * are ignored. `page.request` calls bypass the browser and are never seen.
 */
const createBrowserHealthMonitor = () => {
  const allowances = [];
  const origin = new URL(buildE2eUrl("/")).origin;
  const trackedContexts = new WeakSet();
  const violations = [];

  // Same-origin URLs are shortened to path and query so messages do not depend on the stack port.
  const describeUrl = (url) => {
    const parsedUrl = new URL(url);

    return parsedUrl.origin === origin ? `${parsedUrl.pathname}${parsedUrl.search}` : url;
  };

  const allow = ({ kind, pattern, reason }) => {
    if (!BROWSER_HEALTH_KINDS.includes(kind)) {
      throw new Error(`browserHealth.allow: kind must be one of ${BROWSER_HEALTH_KINDS.join(", ")}`);
    }
    if (!(pattern instanceof RegExp) && (typeof pattern !== "string" || pattern === "")) {
      throw new Error("browserHealth.allow: pattern must be a non-empty string or a RegExp");
    }
    if (typeof reason !== "string" || reason.trim() === "") {
      throw new Error("browserHealth.allow: reason is required");
    }

    allowances.push({ kind, pattern, reason });
  };

  const track = (context) => {
    if (trackedContexts.has(context)) {
      return;
    }
    trackedContexts.add(context);

    context.on("weberror", (webError) => {
      const page = webError.page();
      const location = page ? ` on ${describeUrl(page.url())}` : "";

      violations.push({ kind: "page-error", message: `${webError.error()}${location}` });
    });
    context.on("response", (response) => {
      const requestId = response.headers()["x-request-id"];

      if (response.status() < 500 || !requestId || new URL(response.url()).origin !== origin) {
        return;
      }

      // The request id stays out of the message so repeats of one failure merge into one note.
      const method = response.request().method();
      violations.push({
        kind: "server-error",
        message: `${response.status()} ${method} ${describeUrl(response.url())}`,
        requestId,
      });
    });
  };

  return { allow, allowances, track, violations };
};

/**
 * Creates an authenticated page, re-logging in when the cached session is no longer valid. Must run
 * inside a test, since its contexts (login included) go through `trackContext`.
 */
export const createPreparedPage = async (browser, fixtureName, credentials, preparePage) => {
  const testInfo = base.info();
  let storageState = await getStorageState(browser, fixtureName, credentials, testInfo);
  let context = await browser.newContext({ storageState });
  trackContext(context, testInfo, "fixture");
  let page = await context.newPage();

  if (!(await hasValidSession(page))) {
    storageStateCache.delete(fixtureName);
    await context.close();

    storageState = await getStorageState(browser, fixtureName, credentials, testInfo);
    context = await browser.newContext({ storageState });
    trackContext(context, testInfo, "fixture");
    page = await context.newPage();
  }

  if (preparePage) {
    await preparePage(page);
  }
  startTestPhase(context);

  return {
    page,
    close: async () => context.close(),
  };
};

/** Returns the browser health monitor of a test, creating it on first use. */
const getBrowserHealthMonitor = (testInfo) => {
  let monitor = browserHealthMonitors.get(testInfo);

  if (!monitor) {
    monitor = createBrowserHealthMonitor();
    browserHealthMonitors.set(testInfo, monitor);
  }

  return monitor;
};

/**
 * Returns the route attribution file of the current worker, creating its folder. One file per
 * worker keeps appends from different processes from interleaving.
 */
const getRouteAttributionFile = (testInfo) => {
  const folder = join(testInfo.project.outputDir, "route-attribution");
  mkdirSync(folder, { recursive: true });

  return join(folder, `${testInfo.parallelIndex}.jsonl`);
};

/** Returns a cached authenticated storage state for a fixture, logging in on first use. */
const getStorageState = async (browser, fixtureName, credentials, testInfo) => {
  const cachedState = storageStateCache.get(fixtureName);

  if (cachedState) {
    return cachedState;
  }

  const context = await browser.newContext();
  trackContext(context, testInfo, "fixture");
  const page = await context.newPage();

  await logInWithSeededUser(page, credentials);

  const storageState = await context.storageState();
  storageStateCache.set(fixtureName, storageState);
  await context.close();

  return storageState;
};

/**
 * Returns true only when the dashboard answers 200 directly. Redirects are not followed so an expired session
 * (302 to /log-in) is detected instead of being mistaken for a valid one.
 */
const hasValidSession = async (page) => {
  const response = await page.request.get(buildE2eUrl("/dashboard/user"), { maxRedirects: 0 });

  return response.status() === 200;
};

/**
 * Worker fixture that writes the worker's merged JS coverage at teardown to
 * `js-coverage/raw/e2e-<worker>.json` in the output folder, for `scripts/js-coverage-report.js`.
 * Each entry holds the served script path, its source and its merged V8 function coverage. Scripts
 * whose source Playwright never recorded take the served file in ocg-server/dist (the content hash
 * pins it), so the raw files stay self-contained where the report runs without a server build.
 */
const jsCoverageFixture = async ({}, use, workerInfo) => {
  await use();

  if (!JS_COVERAGE_ENABLED) {
    return;
  }
  await jsCoverageMerges;
  if (jsCoverageByPath.size === 0) {
    return;
  }

  const folder = join(workerInfo.project.outputDir, "js-coverage", "raw");
  mkdirSync(folder, { recursive: true });
  writeFileSync(
    join(folder, `e2e-${workerInfo.workerIndex}.json`),
    JSON.stringify([...jsCoverageByPath.values()].map(withDistSource)),
  );
};

/**
 * Merges the JS coverage of one page into the worker's coverage. Scripts are keyed by URL path, so
 * every stack reports the same script once; the content hash in the path pins its source. Playwright
 * omits the source of scripts it could not read (for example after the page navigated away), so a
 * source seen once is kept.
 */
const mergeJsCoverage = async (entries) => {
  const { Util } = await import("monocart-coverage-reports/util");

  for (const { functions, source, url } of entries) {
    const path = new URL(url).pathname;
    const previous = jsCoverageByPath.get(path);
    const merged = previous ? (await Util.mergeV8Coverage([previous, { functions }])).functions : functions;

    jsCoverageByPath.set(path, { functions: merged, source: source ?? previous?.source, url: path });
  }
};

/**
 * Snapshots the notification queue before the test and its hooks, and deletes every notification
 * (with its orphaned template data and attachments) and custom notification created since
 * then at teardown, so tests never leak queue rows. Exposes `snapshot`,
 * `checkpoint()` (a later cut-off), `expectNew(expectations, { since })` (defaults to the test
 * snapshot) and `list(since)`. Safe only with one worker per database.
 */
const notificationsFixture = async ({}, use) => {
  const snapshot = snapshotNotifications();

  try {
    await use({
      checkpoint: snapshotNotifications,
      expectNew: (expectations, { since = snapshot } = {}) => expectNewNotifications(since, expectations),
      list: (since = snapshot) => listNotificationsSince(since),
      snapshot,
    });
  } finally {
    deleteNotificationsCreatedSince(snapshot);
  }
};

/**
 * Registry of cleanups for data a test owns. `defer(fn)` registers a cleanup, `track(value, cleanup)`
 * registers `cleanup(value)` and returns `value`, and builders create and track common data graphs
 * (`event(options)` takes `insertOwnedEvent` options).
 * `deferProposalByTitle` resolves the proposal ID at cleanup, for proposals created through the UI.
 * Cleanups run LIFO at teardown, continue past failures and rethrow them as one `AggregateError`.
 * Depends on `notifications` so notifications enqueued by cleanups are still deleted afterwards.
 */
const ownedFixture = async ({ notifications: _notifications }, use) => {
  const cleanups = [];
  const defer = (cleanup) => {
    cleanups.push(cleanup);
  };
  const track = (value, cleanup) => {
    defer(() => cleanup(value));

    return value;
  };

  await use({
    attendee: (options) => track(setupOwnedAttendee(options), cleanupOwnedAttendee),
    cohostEvent: (options) =>
      track(setupCohostEvent(options), ({ eventId }) => cleanupCohostEvents([eventId])),
    defer,
    deferProposalByTitle: (userId, title) =>
      defer(() => cleanupSessionProposals({ proposalIds: [readSessionProposalId(userId, title)] })),
    event: (options) => track(insertOwnedEvent(options), ({ eventId }) => cleanupEventsByIds([eventId])),
    sessionProposal: (options) =>
      track(setupSessionProposal(options), ({ proposalId }) =>
        cleanupSessionProposals({ proposalIds: [proposalId] }),
      ),
    track,
  });

  const errors = [];
  for (const cleanup of cleanups.reverse()) {
    try {
      await cleanup();
    } catch (error) {
      errors.push(error);
    }
  }

  if (errors.length > 0) {
    throw new AggregateError(errors, `${errors.length} owned cleanup(s) failed`);
  }
};

/**
 * Opens authenticated fixture pages by name, for tests parameterized by role. Returns
 * `async (fixtureName) => page`; unknown names throw. Pages reuse the per-name storage cache and
 * close in reverse order at teardown. Logging in on a cache miss counts against the test timeout.
 */
const pageAsFixture = async ({ browser, browserHealth: _browserHealth }, use) => {
  const preparedPages = [];

  try {
    await use(async (fixtureName) => {
      if (!Object.hasOwn(AUTHENTICATED_PAGE_FIXTURES, fixtureName)) {
        throw new Error(`Unknown authenticated page fixture: ${fixtureName}`);
      }

      const { credentials, preparePage } = AUTHENTICATED_PAGE_FIXTURES[fixtureName];
      const preparedPage = await createPreparedPage(browser, fixtureName, credentials, preparePage);
      preparedPages.push(preparedPage);

      return preparedPage.page;
    });
  } finally {
    for (const preparedPage of preparedPages.reverse()) {
      await preparedPage.close();
    }
  }
};

/**
 * Annotates the test with its browser health violations, merging repeats of the same kind and
 * message into one note with their count and first request ids: allowed ones as
 * `browser-health-allowed` with the reason, the rest as `browser-health`. In enforce mode, throws
 * one error listing the unallowed violations.
 */
const reportBrowserHealth = ({ allowances, violations }, testInfo) => {
  const groups = new Map();
  for (const { kind, message, requestId } of violations) {
    const description = `${kind}: ${message}`;
    const group = groups.get(description) ?? { count: 0, kind, message, requestIds: [] };
    group.count += 1;
    if (requestId) {
      group.requestIds.push(requestId);
    }
    groups.set(description, group);
  }

  const unallowed = [];
  for (const [description, { count, kind, message, requestIds }] of groups) {
    const details = [];
    if (count > 1) {
      details.push(`x${count}`);
    }
    if (requestIds.length > 0) {
      const listedIds = requestIds.slice(0, MAX_LISTED_REQUEST_IDS).join(", ");
      const more = requestIds.length > MAX_LISTED_REQUEST_IDS ? ", ..." : "";
      details.push(`x-request-id ${listedIds}${more}`);
    }
    const label = details.length > 0 ? `${description} (${details.join(", ")})` : description;
    const allowance = allowances.find(
      ({ kind: allowedKind, pattern }) =>
        allowedKind === kind &&
        (typeof pattern === "string" ? message.includes(pattern) : message.search(pattern) >= 0),
    );

    if (allowance) {
      testInfo.annotations.push({
        type: "browser-health-allowed",
        description: `${label} (allowed: ${allowance.reason})`,
      });
    } else {
      testInfo.annotations.push({ type: "browser-health", description: label });
      unallowed.push(label);
    }
  }

  if (BROWSER_HEALTH_MODE === "enforce" && unallowed.length > 0) {
    throw new Error(
      `Browser health violations (allow expected ones with browserHealth.allow):\n- ${unallowed.join("\n- ")}`,
    );
  }
};

/**
 * Starts the JS coverage of a page and makes `page.close()` stop it first, since a closed page's
 * coverage cannot be read. Coverage survives navigations, so every script the page loads counts.
 */
const startPageJsCoverage = (page) => {
  const start = page.coverage.startJSCoverage({ resetOnNavigation: false }).then(
    () => true,
    () => false,
  );
  jsCoverageStarts.set(page, start);

  const close = page.close.bind(page);
  page.close = async (options) => {
    await stopPageJsCoverage(page);
    return close(options);
  };
};

/** Moves a context tracked in the `fixture` phase to the `test` phase once its page is prepared. */
const startTestPhase = (context) => {
  if (routeAttributionPhases.has(context)) {
    routeAttributionPhases.set(context, "test");
  }
};

/**
 * Stops the JS coverage of a page, once, and queues the app module entries for merging. Pages
 * that are already closed, or whose coverage did not start, are skipped.
 */
const stopPageJsCoverage = async (page) => {
  const start = jsCoverageStarts.get(page);
  jsCoverageStarts.delete(page);
  if (!start || !(await start) || page.isClosed()) {
    return;
  }

  let entries;
  try {
    entries = await page.coverage.stopJSCoverage();
  } catch {
    return;
  }

  const appEntries = entries.filter(
    ({ url }) => URL.canParse(url) && new URL(url).pathname.startsWith(JS_COVERAGE_PATH_PREFIX),
  );
  // A failed merge only loses this page's coverage; the chain keeps serving later stops.
  jsCoverageMerges = jsCoverageMerges
    .then(() => mergeJsCoverage(appEntries))
    .catch((error) => console.warn(`warning: could not merge JS coverage: ${error.message}`));
  await jsCoverageMerges;
};

/**
 * Single hook for every browser context a test uses: the `context` fixture (and so `page`),
 * authenticated page fixtures, `pageAs` pages and their logins, and `browserHealth.track`. Instrumentation that needs every
 * context extends this hook instead of adding another `context` override. `phase` is the route
 * attribution phase the context starts in: `fixture` for logins and pages still being prepared.
 */
const trackContext = (context, testInfo, phase = "test") => {
  getBrowserHealthMonitor(testInfo).track(context);
  if (JS_COVERAGE_ENABLED) {
    trackJsCoverage(context);
  }
  if (ROUTE_ATTRIBUTION_ENABLED) {
    trackRouteAttribution(context, testInfo, phase);
  }
};

/**
 * Records the JS coverage of every page of a Chromium context, starting before the page's first
 * navigation. `context.close()` stops the coverage of the pages still open first; pages closed
 * any other way (a context closed by Playwright's browser teardown, a crashed page) are lost.
 */
const trackJsCoverage = (context) => {
  if (jsCoverageContexts.has(context) || context.browser()?.browserType().name() !== "chromium") {
    return;
  }
  jsCoverageContexts.add(context);

  context.pages().forEach(startPageJsCoverage);
  context.on("page", startPageJsCoverage);

  const close = context.close.bind(context);
  context.close = async (options) => {
    await Promise.all(context.pages().map(stopPageJsCoverage));
    return close(options);
  };
};

/**
 * Appends `{ requestId, testId, file, title, phase }` to the worker's route attribution file for
 * every same-origin response carrying `x-request-id`, so `scripts/route-hits.js --attribution`
 * can join server route hits to tests. The phase is taken when the request starts. `page.request`
 * calls bypass the browser and are never recorded.
 */
const trackRouteAttribution = (context, testInfo, phase) => {
  if (routeAttributionPhases.has(context)) {
    return;
  }
  routeAttributionPhases.set(context, phase);

  const attributionFile = getRouteAttributionFile(testInfo);
  const origin = new URL(buildE2eUrl("/")).origin;
  const requestPhases = new WeakMap();
  const test = {
    testId: testInfo.testId,
    file: relative(testInfo.project.testDir, testInfo.file),
    title: testInfo.titlePath.slice(1).join(" > "),
  };

  context.on("request", (request) => {
    requestPhases.set(request, routeAttributionPhases.get(context));
  });
  context.on("response", (response) => {
    const requestId = response.headers()["x-request-id"];

    if (!requestId || new URL(response.url()).origin !== origin) {
      return;
    }

    const requestPhase = requestPhases.get(response.request()) ?? routeAttributionPhases.get(context);
    appendFileSync(attributionFile, `${JSON.stringify({ requestId, ...test, phase: requestPhase })}\n`);
  });
};

/**
 * Returns a JS coverage entry with its source, reading the served file from ocg-server/dist when
 * Playwright never recorded it. Entries whose file is not in the build stay without a source.
 */
const withDistSource = (entry) => {
  if (typeof entry.source === "string") {
    return entry;
  }

  const path = join(JS_COVERAGE_DIST_DIR, entry.url);

  return existsSync(path) ? { ...entry, source: readFileSync(path, "utf8") } : entry;
};

export const test = base.extend({
  ...Object.fromEntries(
    Object.entries(AUTHENTICATED_PAGE_FIXTURES).map(([fixtureName, definition]) => [
      fixtureName,
      authenticatedPageFixture(fixtureName, definition),
    ]),
  ),
  browserHealth: [browserHealthFixture, { auto: true }],
  context: contextFixture,
  jsCoverage: [jsCoverageFixture, { auto: true, scope: "worker" }],
  notifications: [notificationsFixture, { auto: true }],
  owned: ownedFixture,
  pageAs: pageAsFixture,
});

export { expect };

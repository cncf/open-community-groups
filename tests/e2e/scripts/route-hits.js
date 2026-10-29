import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";

// Reports which routes an e2e run hit, read from the `ocg_route_hits` events of the server logs.
// The server emits one event per response inside its request span when `RUST_LOG` enables the
// `ocg_route_hits` target (parallel.sh does by default). Hits are grouped by method and matched
// route into status buckets. Requests the log-in guard rejected go to the 3xx-log-in bucket
// from the event's redirects_to_log_in field, whatever their status: HTMX and fetch requests are
// not answered with a 3xx. A hit is not an assertion. The report exits non-zero when the logs
// hold no hits or only unmatched (fallback) ones.
//
// With --attribution, hits are joined on their request ID to the records the fixtures write when
// OCG_E2E_ROUTE_ATTRIBUTION=1, which name the test and its phase: `fixture` (log-in and page
// preparation) or `test`. Hits without a record are `unattributed`: `page.request` calls and
// requests made outside the browser. Routes never hit in the `test` phase are flagged. Several
// runs merge by passing all their logs and attribution folders (request IDs are UUIDs).
//
// Usage: route-hits.js [--run-dir DIR] [--attribution DIR]... [--json FILE] [--summary] [LOG]...
//   LOG           - Server log file, or folder with server-*.log files (default: --run-dir)
//   --run-dir     - Parallel run folder (default: $TMPDIR/ocg-e2e-parallel)
//   --attribution - Folder with the *.jsonl route attribution files of the same run (repeatable)
//   --json        - File to write the full report to
//   --summary     - Print counts, flagged routes and 5xx responses only, without the route list

const ATTRIBUTION_FILE_PATTERN = /\.jsonl$/u;
const ATTRIBUTION_PHASES = ["fixture", "test", "unattributed"];
const BUCKETS = ["2xx", "3xx", "3xx-log-in", "4xx", "5xx"];
const FALLBACK_PATH = "fallback";
const FIXTURE_PHASE = "fixture";
const LOG_FILE_PATTERN = /^server-.*\.log$/u;
const LOG_IN_BUCKET = "3xx-log-in";
const REQUEST_SPAN_NAME = "request";
const ROUTE_HITS_TARGET = "ocg_route_hits";
const TEST_PHASE = "test";
const UNATTRIBUTED_PHASE = "unattributed";

/**
 * Builds the report, prints it and optionally writes it as JSON.
 */
const main = () => {
  const options = readOptions();
  const logs = resolveLogFiles(options);

  // Read the route-hit events of every server log
  const hits = [];
  let withoutSpan = 0;
  for (const log of logs) {
    for (const hit of readRouteHits(log)) {
      if (hit) {
        hits.push(hit);
      } else {
        withoutSpan += 1;
      }
    }
  }
  if (withoutSpan > 0) {
    console.warn(
      `warning: ${withoutSpan} route hits have no request span; ` +
        "RUST_LOG must enable both ocg_server=debug and ocg_route_hits=debug",
    );
  }
  if (hits.length === 0) {
    throw new Error(
      `No route hits in ${logs.join(", ")}; RUST_LOG must enable ocg_route_hits=debug ` +
        "(parallel.sh does by default)",
    );
  }
  if (hits.every((hit) => hit.path === FALLBACK_PATH)) {
    throw new Error(
      `Every route hit in ${logs.join(", ")} matched no route (${FALLBACK_PATH}); ` +
        "is the trace layer still inside the router?",
    );
  }

  const report = buildReport(hits, logs, withoutSpan);
  if (options.attribution) {
    report.attribution = attributeHits(report, hits, readAttribution(options.attribution));
  }
  printReport(report, options.summary);
  if (options.json) {
    writeFileSync(options.json, `${JSON.stringify(report, null, 2)}\n`);
  }
};

/**
 * Joins route hits to their attribution records, adds the hits per phase and the tests that hit
 * each route in the `test` phase to the report routes, and flags routes never hit in that phase.
 * @param {object} report - Report built by `buildReport`; its routes gain an `attribution` field.
 * @param {{method: string, path: string, requestId: string}[]} hits - Parsed route hits.
 * @param {{files: string[], records: Map<string, {file: string, phase: string, title: string}>}}
 * attribution - Attribution records by request ID.
 * @returns {object} Attribution totals, flagged routes and records without a route hit.
 */
const attributeHits = (report, hits, attribution) => {
  const routes = new Map(report.routes.map((route) => [`${route.method} ${route.path}`, route]));
  const routeTests = new Map();
  const totals = emptyPhases();
  const usedRequestIds = new Set();

  for (const route of report.routes) {
    route.attribution = { ...emptyPhases(), tests: [] };
    routeTests.set(route, new Set());
  }
  for (const hit of hits) {
    const route = routes.get(`${hit.method} ${hit.path}`);
    const record = attribution.records.get(hit.requestId);
    const phase = record ? record.phase : UNATTRIBUTED_PHASE;
    route.attribution[phase] += 1;
    totals[phase] += 1;
    if (record) {
      usedRequestIds.add(hit.requestId);
    }
    if (phase === TEST_PHASE) {
      routeTests.get(route).add(`${record.file}: ${record.title}`);
    }
  }
  for (const [route, tests] of routeTests) {
    route.attribution.tests = [...tests].sort(compareStrings);
  }

  return {
    files: attribution.files,
    flaggedRoutes: report.routes
      .filter(({ attribution: { test }, path }) => test === 0 && path !== FALLBACK_PATH)
      .map(({ attribution: { fixture, unattributed }, method, path }) => ({
        fixture,
        method,
        path,
        unattributed,
      })),
    recordsWithoutHit: attribution.records.size - usedRequestIds.size,
    totals,
  };
};

/**
 * Groups route hits by method and matched route into status buckets.
 * @param {{bucket: string, method: string, path: string, requestId: string, status: number,
 * uri: string}[]} hits - Parsed route hits.
 * @param {string[]} logs - Server logs read.
 * @param {number} withoutSpan - Route hits skipped because they had no request span.
 * @returns {object} Totals, every hit route with its buckets, and the 5xx responses.
 */
const buildReport = (hits, logs, withoutSpan) => {
  const routes = new Map();
  const totals = emptyBuckets();

  for (const hit of hits) {
    const key = `${hit.method} ${hit.path}`;
    const route = routes.get(key) ?? { buckets: emptyBuckets(), hits: 0, method: hit.method, path: hit.path };
    route.buckets[hit.bucket] = (route.buckets[hit.bucket] ?? 0) + 1;
    route.hits += 1;
    routes.set(key, route);
    totals[hit.bucket] = (totals[hit.bucket] ?? 0) + 1;
  }

  return {
    logs,
    routes: [...routes.values()].sort(
      (a, b) => compareStrings(a.path, b.path) || compareStrings(a.method, b.method),
    ),
    serverErrors: hits
      .filter((hit) => hit.bucket === "5xx")
      .map(({ method, path, requestId, status, uri }) => ({ method, path, requestId, status, uri })),
    totals: { buckets: totals, hits: hits.length, routes: routes.size, withoutSpan },
  };
};

/**
 * Returns the status bucket of a response.
 * @param {number} status - Response status code.
 * @param {boolean} redirectsToLogIn - Whether the log-in guard rejected the request.
 * @returns {string} Bucket name, such as `2xx` or `3xx-log-in`.
 */
const classifyStatus = (status, redirectsToLogIn) =>
  redirectsToLogIn ? LOG_IN_BUCKET : `${Math.floor(status / 100)}xx`;

/**
 * Compares two strings by code unit, independently of the locale.
 * @param {string} a - First string.
 * @param {string} b - Second string.
 * @returns {number} Negative, zero or positive, as for `Array.prototype.sort`.
 */
const compareStrings = (a, b) => {
  if (a === b) {
    return 0;
  }

  return a < b ? -1 : 1;
};

/**
 * Returns a counter per bucket, all zero.
 * @returns {Record<string, number>} Counters keyed by bucket name.
 */
const emptyBuckets = () => Object.fromEntries(BUCKETS.map((bucket) => [bucket, 0]));

/**
 * Returns a counter per attribution phase, all zero.
 * @returns {Record<string, number>} Counters keyed by phase name.
 */
const emptyPhases = () => Object.fromEntries(ATTRIBUTION_PHASES.map((phase) => [phase, 0]));

/**
 * Formats the non-zero buckets of a counter set.
 * @param {Record<string, number>} buckets - Counters keyed by bucket name.
 * @returns {string} Bucket counts such as `2xx 3, 4xx 1`.
 */
const formatBuckets = (buckets) =>
  Object.entries(buckets)
    .filter(([, count]) => count > 0)
    .map(([bucket, count]) => `${bucket} ${count}`)
    .join(", ");

/**
 * Removes the trailing slash of a matched route, so nested root routes match the manifest.
 * @param {string} path - Matched route template.
 * @returns {string} Normalized route template.
 */
const normalizePath = (path) => (path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path);

/**
 * Parses one server log line into a route hit.
 * @param {string} line - Log line, a JSON object for events.
 * @returns {object|null|undefined} Route hit, null for a route-hit event without its request
 * span, or undefined for any other line.
 */
const parseRouteHit = (line) => {
  if (!line.startsWith("{")) {
    return undefined;
  }
  let entry;
  try {
    entry = JSON.parse(line);
  } catch {
    return undefined;
  }
  if (entry.target !== ROUTE_HITS_TARGET) {
    return undefined;
  }

  // The event runs inside the request span, which carries the request fields
  const span = entry.spans?.find((candidate) => candidate.name === REQUEST_SPAN_NAME);
  const fields = entry.fields ?? {};
  if (typeof span?.matched_path !== "string" || typeof fields.status !== "number") {
    return null;
  }

  return {
    bucket: classifyStatus(fields.status, fields.redirects_to_log_in === true),
    method: span.method,
    path: normalizePath(span.matched_path),
    requestId: span.request_id ?? "",
    status: fields.status,
    uri: span.uri,
  };
};

/**
 * Prints the report.
 * @param {object} report - Report built by `buildReport`.
 * @param {boolean} [summary] - Print counts and 5xx responses only.
 */
const printReport = (report, summary = false) => {
  const { attribution, logs, routes, serverErrors, totals } = report;
  const fallback = routes
    .filter(({ path }) => path === FALLBACK_PATH)
    .reduce((sum, { hits }) => sum + hits, 0);

  console.log(`==> Route hits (${logs.join(", ")})`);
  console.log(`  Hits: ${totals.hits} (${formatBuckets(totals.buckets)})`);
  console.log(`  Routes hit (method and matched route): ${totals.routes}`);
  console.log(`  Unmatched (${FALLBACK_PATH}) hits: ${fallback}`);
  if (!summary) {
    for (const { attribution: routeAttribution, buckets, method, path } of routes) {
      const tests = routeAttribution ? ` (tests: ${routeAttribution.tests.length})` : "";
      console.log(`    - ${method} ${path}: ${formatBuckets(buckets)}${tests}`);
    }
  }
  if (attribution) {
    console.log(`  Attribution (${attribution.files.join(", ")}): ${formatBuckets(attribution.totals)}`);
    console.log(`  Attribution records without a route hit: ${attribution.recordsWithoutHit}`);
    console.log(`  Routes never hit in the test phase: ${attribution.flaggedRoutes.length}`);
    for (const { fixture, method, path, unattributed } of attribution.flaggedRoutes) {
      console.log(`    - ${method} ${path}: ${formatBuckets({ fixture, unattributed })}`);
    }
  }
  console.log(`  5xx responses: ${serverErrors.length}`);
  for (const { method, path, requestId, status, uri } of serverErrors) {
    console.log(`    - ${status} ${method} ${uri} (${path}, request ${requestId || "unknown"})`);
  }
};

/**
 * Parses the command-line options.
 * @returns {{attribution?: string[], json?: string, logs: string[], "run-dir": string, summary?: boolean}}
 * Options.
 */
const readOptions = () => {
  const { positionals, values } = parseArgs({
    allowPositionals: true,
    options: {
      attribution: { multiple: true, type: "string" },
      json: { type: "string" },
      "run-dir": { default: join(tmpdir(), "ocg-e2e-parallel"), type: "string" },
      summary: { type: "boolean" },
    },
  });

  return { ...values, logs: positionals };
};

/**
 * Reads the route attribution records of one or more folders, keyed by request ID.
 * @param {string[]} folders - Folders with the *.jsonl files written by the fixtures.
 * @returns {{files: string[], records: Map<string, {file: string, phase: string, title: string}>}}
 * Files read and records by request ID.
 */
const readAttribution = (folders) => {
  const files = [];
  for (const folder of folders) {
    if (!existsSync(folder) || !statSync(folder).isDirectory()) {
      throw new Error(`${folder} is not a folder; run the tests with OCG_E2E_ROUTE_ATTRIBUTION=1 first`);
    }
    const folderFiles = readdirSync(folder)
      .filter((name) => ATTRIBUTION_FILE_PATTERN.test(name))
      .sort(compareStrings)
      .map((name) => join(folder, name));
    if (folderFiles.length === 0) {
      throw new Error(`No *.jsonl files in ${folder}; run the tests with OCG_E2E_ROUTE_ATTRIBUTION=1`);
    }
    files.push(...folderFiles);
  }

  const records = new Map();
  for (const file of files) {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      if (line.trim() === "") {
        continue;
      }
      const { file: testFile, phase, requestId, title } = JSON.parse(line);
      if (phase !== FIXTURE_PHASE && phase !== TEST_PHASE) {
        throw new Error(`Unknown phase "${phase}" in ${file}`);
      }
      records.set(requestId, { file: testFile, phase, title });
    }
  }

  return { files, records };
};

/**
 * Reads the route hits of a server log.
 * @param {string} log - Server log file.
 * @returns {(object|null)[]} Route hits, null for those without a request span.
 */
const readRouteHits = (log) =>
  readFileSync(log, "utf8")
    .split("\n")
    .map(parseRouteHit)
    .filter((hit) => hit !== undefined);

/**
 * Lists the server logs to read: the given files, and the server-*.log files of the given
 * folders or of the run folder.
 * @param {{logs: string[], "run-dir": string}} options - Command-line options.
 * @returns {string[]} Server log files.
 */
const resolveLogFiles = (options) => {
  const targets = options.logs.length > 0 ? options.logs : [options["run-dir"]];
  const logs = [];

  for (const target of targets) {
    if (!existsSync(target)) {
      throw new Error(`${target} not found; run just e2e-tests-parallel first or pass a server log`);
    }
    if (statSync(target).isDirectory()) {
      const files = readdirSync(target)
        .filter((name) => LOG_FILE_PATTERN.test(name))
        .sort(compareStrings);
      if (files.length === 0) {
        throw new Error(`No server-*.log files in ${target}`);
      }
      logs.push(...files.map((name) => join(target, name)));
    } else {
      logs.push(target);
    }
  }

  return logs;
};

try {
  main();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}

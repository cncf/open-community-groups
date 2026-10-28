import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

import { findCoveredByProblem } from "./covered-by.js";

// Checks the route hits of an e2e run against the route manifest and the route coverage
// allowlist. A route is covered by a hit below 400 that is not a log-in redirect (the `2xx` and
// `3xx` buckets of route-hits.js). Every other manifest route needs an allowlist entry giving a
// reason and the test that covers it instead. A hit is not an assertion, and only complete runs
// give meaningful lists.
//
// Without --blocking the check only reports. With --blocking it exits non-zero on uncovered routes
// without an entry and on allowlist errors: entries not in the manifest, duplicated or with an
// unresolvable `coveredBy`. It always warns, without failing, on allowlisted routes this run
// covered, on 5xx hits of routes without a `non-2xx-by-design` entry and on hit routes missing
// from the manifest.
//
// Usage: route-coverage.js [--run-dir DIR] [--route-hits FILE] [--json FILE] [--summary] [--blocking]
//   --run-dir    - Parallel run folder (default: $TMPDIR/ocg-e2e-parallel)
//   --route-hits - Report written by route-hits.js --json (default: <run-dir>/route-hits.json)
//   --json       - File to write the full report to
//   --summary    - Print counts, allowlist errors and warnings only, without the route lists
//                  (with --blocking it still lists the uncovered routes)
//   --blocking   - Exit non-zero on uncovered routes without an entry and on allowlist errors

const ALLOWLIST_PATH = fileURLToPath(new URL("../coverage/route-coverage-allowlist.json", import.meta.url));
const COVERED_BUCKETS = ["2xx", "3xx"];
const COVERED_BY_SCHEMES = ["e2e", "pgtap", "rust"];
const ENTRY_FIELDS = ["coveredBy", "method", "note", "path", "reason"];
const FALLBACK_PATH = "fallback";
const MANIFEST_PATH = fileURLToPath(new URL("../coverage/route-manifest.json", import.meta.url));
const NON_2XX_REASON = "non-2xx-by-design";
const REASONS = ["disabled-in-e2e", NON_2XX_REASON, "pgtap-only", "provider-only", "rust-only", "untraced"];
const REPO_ROOT = fileURLToPath(new URL("../../..", import.meta.url));
const SERVER_ERROR_BUCKET = "5xx";

/**
 * Builds the report, prints it, optionally writes it as JSON and fails when blocking.
 */
const main = () => {
  const options = readOptions();
  const routeHitsPath = options["route-hits"] ?? join(options["run-dir"], "route-hits.json");
  const report = buildReport(readManifest(), readRouteHits(routeHitsPath), readAllowlist());

  report.routeHits = routeHitsPath;
  printReport(report, options.summary, options.blocking);
  if (options.json) {
    writeFileSync(options.json, `${JSON.stringify(report, null, 2)}\n`);
  }

  const { allowlistErrors, uncovered } = report.totals;
  if (options.blocking && (uncovered > 0 || allowlistErrors > 0)) {
    throw new Error(
      `route coverage check failed: ${uncovered} uncovered routes without an allowlist entry, ` +
        `${allowlistErrors} allowlist errors`,
    );
  }
};

/**
 * Classifies every manifest route as covered, allowlisted or uncovered, and checks the allowlist.
 * @param {{method: string, path: string}[]} manifest - Declared routes.
 * @param {{buckets: Record<string, number>, method: string, path: string}[]} hitRoutes - Hit
 * routes from route-hits.js.
 * @param {{coveredBy: string, method: string, note: string, path: string, reason: string}[]}
 * allowlist - Allowlist entries.
 * @returns {object} Routes by class, allowlist errors, warnings and totals.
 */
const buildReport = (manifest, hitRoutes, allowlist) => {
  const allowlistErrors = [];
  const entries = new Map();
  const hits = new Map(hitRoutes.map((route) => [routeKey(route), route]));
  const manifestKeys = new Set(manifest.map(routeKey));
  const warnings = [];

  // Check every entry names a declared route once and a covering test that exists
  for (const entry of allowlist) {
    const key = routeKey(entry);
    if (entries.has(key)) {
      allowlistErrors.push(`${key}: duplicate entry`);
    }
    entries.set(key, entry);
    if (!manifestKeys.has(key)) {
      allowlistErrors.push(`${key}: not in the route manifest`);
    }
    const problem = findCoveredByProblem(entry.coveredBy, COVERED_BY_SCHEMES);
    if (problem) {
      allowlistErrors.push(`${key}: ${problem}`);
    }
  }

  // Classify the manifest routes
  const allowlisted = [];
  const covered = [];
  const uncovered = [];
  for (const route of manifest) {
    const key = routeKey(route);
    const buckets = hits.get(key)?.buckets ?? {};
    const entry = entries.get(key);
    const isCovered = COVERED_BUCKETS.some((bucket) => (buckets[bucket] ?? 0) > 0);
    const serverErrors = buckets[SERVER_ERROR_BUCKET] ?? 0;
    const explainsServerErrors = entry?.reason === NON_2XX_REASON && serverErrors > 0;

    if (isCovered) {
      covered.push({ buckets, method: route.method, path: route.path });
      if (entry && !explainsServerErrors) {
        const detail = entry.reason === NON_2XX_REASON ? "covered with no 5xx response" : "covered";
        warnings.push(`${key}: allowlisted (${entry.reason}) but ${detail} in this run; remove the entry`);
      }
    } else if (entry) {
      allowlisted.push({
        buckets,
        coveredBy: entry.coveredBy,
        method: route.method,
        path: route.path,
        reason: entry.reason,
      });
    } else {
      uncovered.push({ buckets, method: route.method, path: route.path });
    }
    if (serverErrors > 0 && entry?.reason !== NON_2XX_REASON) {
      warnings.push(`${key}: ${serverErrors} 5xx responses (see the route hits report for request IDs)`);
    }
  }

  // Hits outside the manifest mean a stale manifest
  for (const route of hitRoutes) {
    if (route.path !== FALLBACK_PATH && !manifestKeys.has(routeKey(route))) {
      warnings.push(`${routeKey(route)}: hit but not in the route manifest; run just e2e-route-manifest`);
    }
  }

  return {
    allowlistErrors,
    allowlisted,
    covered,
    totals: {
      allowlistErrors: allowlistErrors.length,
      allowlisted: allowlisted.length,
      covered: covered.length,
      routes: manifest.length,
      uncovered: uncovered.length,
      warnings: warnings.length,
    },
    uncovered,
    warnings,
  };
};

/**
 * Formats the non-zero buckets of a hit route.
 * @param {Record<string, number>} buckets - Hit counts keyed by bucket name.
 * @returns {string} Bucket counts such as `4xx 1`, or `no hits`.
 */
const formatBuckets = (buckets) =>
  Object.entries(buckets)
    .filter(([, count]) => count > 0)
    .map(([bucket, count]) => `${bucket} ${count}`)
    .join(", ") || "no hits";

/**
 * Counts the allowlisted routes per reason.
 * @param {{reason: string}[]} allowlisted - Allowlisted uncovered routes.
 * @returns {string} Counts such as `provider-only 4, untraced 1`, or `none`.
 */
const formatReasons = (allowlisted) =>
  REASONS.map((reason) => [reason, allowlisted.filter((route) => route.reason === reason).length])
    .filter(([, count]) => count > 0)
    .map(([reason, count]) => `${reason} ${count}`)
    .join(", ") || "none";

/**
 * Prints the report.
 * @param {object} report - Report built by `buildReport`.
 * @param {boolean} [summary] - Print counts, allowlist errors and warnings only.
 * @param {boolean} [blocking] - Also list the uncovered routes in a summary.
 */
const printReport = (report, summary = false, blocking = false) => {
  const { allowlistErrors, allowlisted, routeHits, totals, uncovered, warnings } = report;
  const list = (items) => {
    for (const item of items) {
      console.log(`    - ${item}`);
    }
  };

  console.log(`==> Route coverage (${routeHits})`);
  console.log(`  Manifest routes: ${totals.routes}`);
  console.log(`  Covered (a 2xx or 3xx hit that is not a log-in redirect): ${totals.covered}`);
  console.log(`  Allowlisted: ${totals.allowlisted} (${formatReasons(allowlisted)})`);
  if (!summary) {
    list(
      allowlisted.map(({ coveredBy, method, path, reason }) => `${method} ${path}: ${reason}, ${coveredBy}`),
    );
  }
  console.log(`  Uncovered without an allowlist entry: ${totals.uncovered}`);
  if (!summary || blocking) {
    list(uncovered.map(({ buckets, method, path }) => `${method} ${path} (${formatBuckets(buckets)})`));
  }
  console.log(`  Allowlist errors: ${totals.allowlistErrors}`);
  list(allowlistErrors);
  console.log(`  Warnings: ${totals.warnings}`);
  list(warnings);
};

/**
 * Reads the route coverage allowlist and checks its shape.
 * @returns {{coveredBy: string, method: string, note: string, path: string, reason: string}[]}
 * Allowlist entries.
 */
const readAllowlist = () => {
  const entries = readJson(ALLOWLIST_PATH);
  const invalid = Array.isArray(entries)
    ? entries.find(
        (entry) =>
          ENTRY_FIELDS.some((field) => typeof entry?.[field] !== "string" || !entry[field]) ||
          !REASONS.includes(entry.reason),
      )
    : entries;

  if (invalid !== undefined) {
    throw new Error(
      `${relative(REPO_ROOT, ALLOWLIST_PATH)} must be an array of { method, path, reason, note, ` +
        `coveredBy } objects with a reason among ${REASONS.join(", ")} (got ${JSON.stringify(invalid)})`,
    );
  }

  return entries;
};

/**
 * Reads a JSON file.
 * @param {string} path - File path.
 * @returns {unknown} Parsed content.
 */
const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));

/**
 * Reads the route manifest.
 * @returns {{method: string, path: string}[]} Declared routes.
 */
const readManifest = () => readJson(MANIFEST_PATH);

/**
 * Parses the command-line options.
 * @returns {{blocking?: boolean, json?: string, "route-hits"?: string, "run-dir": string,
 * summary?: boolean}} Options.
 */
const readOptions = () =>
  parseArgs({
    options: {
      blocking: { type: "boolean" },
      json: { type: "string" },
      "route-hits": { type: "string" },
      "run-dir": { default: join(tmpdir(), "ocg-e2e-parallel"), type: "string" },
      summary: { type: "boolean" },
    },
  }).values;

/**
 * Reads the hit routes of a route-hits.js report.
 * @param {string} path - Report written by route-hits.js --json.
 * @returns {{buckets: Record<string, number>, method: string, path: string}[]} Hit routes.
 */
const readRouteHits = (path) => {
  if (!existsSync(path)) {
    throw new Error(`${path} not found; run just e2e-tests-parallel or just e2e-route-hits --json first`);
  }
  const { routes } = readJson(path);
  if (!Array.isArray(routes)) {
    throw new Error(`${path} is not a route-hits.js report (no routes list)`);
  }

  return routes;
};

/**
 * Returns the key of a route.
 * @param {{method: string, path: string}} route - Route with its method and template.
 * @returns {string} Key such as `GET /dashboard/user`.
 */
const routeKey = ({ method, path }) => `${method} ${path}`;

try {
  main();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}

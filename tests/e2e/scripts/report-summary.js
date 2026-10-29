import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parseArgs, stripVTControlCharacters } from "node:util";

// Prints a Markdown summary of merged e2e runs: test totals, run durations and failed tests.
// The browser-health and navigation-retry counts come from the diagnostics reporter, which runs
// in the same merge. CI appends the output to the step summary.
//
// Usage: report-summary.js --json FILE [--runs-dir DIR]
//   --json     - JSON report written by `npx playwright merge-reports --config merge.config.js`
//   --runs-dir - Folder with one archived run per subfolder (OCG_E2E_RUN_ARCHIVE in parallel.sh),
//                whose `run.json` gives its timing (`{ durationSecs, exitCode, name }`)

// Failed tests listed before the rest are only counted.
const MAX_LISTED_FAILURES = 100;

// Longest error excerpt shown per failed test.
const MAX_ERROR_LENGTH = 300;

// Test statuses of the JSON report that count as failures.
const FAILED_STATUSES = new Set(["flaky", "unexpected"]);

/**
 * Reads the reports and prints the summary.
 */
const main = () => {
  const options = readOptions();
  if (!options.json) {
    throw new Error("--json is required");
  }

  const report = readJson(options.json);
  const runs = options["runs-dir"] ? readRunTimings(options["runs-dir"]) : [];

  console.log(buildSummary(report, runs));
};

/**
 * Builds the Markdown summary.
 * @param {object} report - Merged Playwright JSON report.
 * @param {{durationSecs: number, exitCode: number, name: string}[]} runs - Run timings.
 * @returns {string} Markdown summary.
 */
const buildSummary = (report, runs) => {
  const { duration, expected, flaky, skipped, unexpected } = report.stats;
  const lines = [
    "## E2E run summary",
    "",
    "| Passed | Failed | Flaky | Skipped | Duration |",
    "| --- | --- | --- | --- | --- |",
    `| ${expected} | ${unexpected} | ${flaky} | ${skipped} | ${formatDuration(duration / 1000)} |`,
  ];

  lines.push("", "### Run durations", "");
  if (runs.length === 0) {
    lines.push("No run timings found.");
  } else {
    lines.push("| Run | Duration (stacks and tests) | Exit code |", "| --- | --- | --- |");
    for (const { durationSecs, exitCode, name } of runs) {
      lines.push(`| ${name} | ${formatDuration(durationSecs)} | ${exitCode} |`);
    }
  }

  const failures = collectFailures(report.suites ?? []);
  lines.push("", `### Failed tests (${failures.length})`, "");
  if (failures.length === 0) {
    lines.push("None.");
  }
  for (const { error, status, test } of failures.slice(0, MAX_LISTED_FAILURES)) {
    lines.push(`- ${test} (${status}): ${error}`);
  }
  if (failures.length > MAX_LISTED_FAILURES) {
    lines.push(`- ... and ${failures.length - MAX_LISTED_FAILURES} more`);
  }

  return lines.join("\n");
};

/**
 * Collects the failed and flaky tests of the report, sorted by test.
 * @param {object[]} suites - Suites of the JSON report.
 * @param {string[]} titles - Titles of the enclosing describe blocks.
 * @returns {{error: string, status: string, test: string}[]} Failed tests.
 */
const collectFailures = (suites, titles = []) => {
  const failures = [];

  for (const suite of suites) {
    // File suites are titled with their path, which the spec location already shows.
    const suiteTitles = titles.length === 0 && suite.title === suite.file ? [] : [...titles, suite.title];

    for (const spec of suite.specs ?? []) {
      for (const test of spec.tests ?? []) {
        if (!FAILED_STATUSES.has(test.status)) {
          continue;
        }
        const name = [...suiteTitles, spec.title].join(" › ");
        failures.push({
          error: firstError(test.results ?? []),
          status: test.status,
          test: `[${test.projectName}] ${spec.file}:${spec.line} › ${name}`,
        });
      }
    }
    failures.push(...collectFailures(suite.suites ?? [], suiteTitles));
  }

  return titles.length === 0 ? failures.toSorted((a, b) => a.test.localeCompare(b.test)) : failures;
};

/**
 * Returns the first line of the first error of the results, without terminal colors.
 * @param {object[]} results - Results of one test.
 * @returns {string} Error excerpt, or a placeholder when no result has an error.
 */
const firstError = (results) => {
  const message = results.flatMap((result) => result.errors ?? []).find((error) => error.message)?.message;
  if (!message) {
    return "no error message";
  }

  const line = stripVTControlCharacters(message).trim().split("\n")[0];

  return line.length > MAX_ERROR_LENGTH ? `${line.slice(0, MAX_ERROR_LENGTH)}...` : line;
};

/**
 * Formats a duration in seconds as minutes and seconds.
 * @param {number} seconds - Duration in seconds.
 * @returns {string} Duration such as `7m 42s`.
 */
const formatDuration = (seconds) => {
  const rounded = Math.round(seconds);

  return `${Math.floor(rounded / 60)}m ${rounded % 60}s`;
};

/**
 * Reads a JSON file.
 * @param {string} path - File path.
 * @returns {any} Parsed content.
 */
const readJson = (path) => {
  if (!existsSync(path)) {
    throw new Error(`${path} not found; run npx playwright merge-reports --config merge.config.js first`);
  }

  return JSON.parse(readFileSync(path, "utf8"));
};

/**
 * Parses the command line options.
 * @returns {{json?: string, "runs-dir"?: string}} Options.
 */
const readOptions = () =>
  parseArgs({
    options: {
      json: { type: "string" },
      "runs-dir": { type: "string" },
    },
  }).values;

/**
 * Reads the timings of the archived runs, sorted by run name.
 * @param {string} dir - Folder with one archived run per subfolder.
 * @returns {{durationSecs: number, exitCode: number, name: string}[]} Run timings.
 */
const readRunTimings = (dir) =>
  readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && existsSync(join(dir, entry.name, "run.json")))
    .map((entry) => readJson(join(dir, entry.name, "run.json")))
    .toSorted((a, b) => a.name.localeCompare(b.name, "en", { numeric: true }));

try {
  main();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}

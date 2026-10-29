import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

import { CoverageReport } from "monocart-coverage-reports";
import { Util } from "monocart-coverage-reports/util";

// Merges the V8 JS coverage of e2e runs (OCG_E2E_JS_COVERAGE=1, written by the `jsCoverage`
// fixture) and of the unit tests (`--coverage`, written by tests/unit/web-test-runner.config.mjs)
// with monocart, and classifies every module in ocg-server/static/js by the suites that ran it:
// both, e2e only, unit only or neither. A suite runs a module when it loads it, so the line
// percentages tell how much of it ran. Served scripts are mapped back to their repository file:
// the 8-hex content hash is stripped from e2e paths, and the import specifiers the e2e server
// (hashed paths) and the unit test server (the Lit bundle) rewrite are aligned with the source.
// Entries that do not align (a server built from other sources) or whose source is unknown are
// skipped and counted. The report is non-blocking: it exits non-zero only when it has no coverage.
//
// Usage: js-coverage-report.js [--e2e DIR]... [--unit DIR] [--out DIR] [--summary]
//   --e2e     - Raw e2e coverage folder (repeatable; default: tests/e2e/test-results/js-coverage/raw)
//   --unit    - Raw unit coverage folder (default: tests/unit/coverage/raw)
//   --out     - Report folder (default: tests/e2e/coverage-reports/js-coverage); its e2e/, unit/
//               and merged/ HTML reports and js-coverage-matrix.json are replaced
//   --summary - Print counts only, without the per-file matrix

const APP_MODULES_DIR = "ocg-server/static/js";
// Content hash the server adds to static asset file names (`name.<hash>.js`).
const CONTENT_HASH_PATTERN = /\.[0-9a-f]{8}(?=\.js$)/u;
// Server build output the e2e server serves `/static/` from.
const DIST_DIR = "ocg-server/dist";
const REPORT_NAMES = ["e2e", "unit", "merged"];
const REPO_ROOT = fileURLToPath(new URL("../../..", import.meta.url));
// URL path prefix of the static assets the e2e server serves.
const STATIC_PATH_PREFIX = "/static/";
const STATUSES = ["both", "e2e-only", "unit-only", "neither"];
const SUITES = ["e2e", "unit"];
// A rewritten import specifier changes one token: no whitespace or quotes in the changed span.
const TOKEN_PATTERN = /^[^\s"'`]*$/u;
// Path prefix the unit test server serves the repository under.
const UNIT_PATH_PREFIX = "/ocg-server";

/**
 * Reads the raw coverage, writes the reports and the matrix, and prints the summary.
 * @returns {Promise<void>} Resolves once the reports are written.
 */
const main = async () => {
  const options = readOptions();
  const sources = readAppModules();
  const suites = {
    e2e: readSuite(options.e2e, sources),
    unit: readSuite([options.unit], sources),
  };
  if (SUITES.every((suite) => suites[suite].files.size === 0)) {
    throw new Error(
      `No JS coverage in ${[...options.e2e, options.unit].join(", ")}; run the e2e tests with ` +
        "OCG_E2E_JS_COVERAGE=1 or the unit tests with --coverage first",
    );
  }

  // Replace the previous reports, so a suite without coverage leaves no stale report behind
  for (const name of REPORT_NAMES) {
    rmSync(join(options.out, name), { force: true, recursive: true });
  }
  mkdirSync(options.out, { recursive: true });
  const results = {};
  for (const suite of SUITES) {
    const entries = await mergeSuiteEntries(suites[suite].files, sources);
    suites[suite].entries = entries;
    results[suite] = entries.length > 0 ? await generateReport(suite, entries, options.out) : undefined;
  }
  results.merged = await generateReport(
    "merged",
    SUITES.flatMap((suite) => suites[suite].entries),
    options.out,
  );

  const report = buildReport(sources, suites, results, options.out);
  printReport(report, options.summary);
  writeFileSync(join(options.out, "js-coverage-matrix.json"), `${JSON.stringify(report, null, 2)}\n`);
};

/**
 * Builds the per-file matrix and the totals.
 * @param {Map<string, string>} sources - Source per app module path.
 * @param {object} suites - Raw coverage per suite.
 * @param {object} results - Monocart results per suite and merged (undefined for empty suites).
 * @param {string} outDir - Report folder.
 * @returns {object} Report written to js-coverage-matrix.json.
 */
const buildReport = (sources, suites, results, outDir) => {
  const linesPct = (result, file) =>
    result?.files.find(({ sourcePath }) => sourcePath === file)?.summary.lines.pct ?? null;
  const files = [...sources.keys()].map((file) => {
    const ranBy = SUITES.filter((suite) => suites[suite].files.has(file));
    const status = ranBy.length === 2 ? "both" : ranBy.length === 0 ? "neither" : `${ranBy[0]}-only`;

    return {
      e2eLinesPct: linesPct(results.e2e, file),
      file,
      mergedLinesPct: linesPct(results.merged, file),
      status,
      unitLinesPct: linesPct(results.unit, file),
    };
  });

  return {
    files,
    inputs: Object.fromEntries(
      SUITES.map((suite) => [
        suite,
        {
          dirs: suites[suite].dirs.map(displayPath),
          rawFiles: suites[suite].rawFiles,
          skippedOutsideAppModules: suites[suite].skippedOutside,
          skippedUnaligned: suites[suite].skippedUnaligned,
          skippedWithoutSource: suites[suite].skippedWithoutSource,
        },
      ]),
    ),
    linesPct: Object.fromEntries(
      [...SUITES, "merged"].map((name) => [name, results[name]?.summary.lines.pct ?? null]),
    ),
    reportDir: displayPath(outDir),
    totals: Object.fromEntries(
      STATUSES.map((status) => [status, files.filter((file) => file.status === status).length]),
    ),
  };
};

/**
 * Returns a function mapping offsets of a served script to offsets of its repository source. The
 * servers only rewrite import specifiers, so both texts have the same lines and each changed line
 * differs in one token; offsets inside that token map to its start.
 * @param {string} served - Script source as served.
 * @param {string} source - Repository source.
 * @returns {((offset: number) => number)|undefined} Offset mapper, or undefined when the texts
 * differ in more than rewritten specifiers.
 */
const createOffsetMapper = (served, source) => {
  if (served === source) {
    return (offset) => offset;
  }

  const servedLines = served.split("\n");
  const sourceLines = source.split("\n");
  if (servedLines.length !== sourceLines.length) {
    return undefined;
  }

  // Per line: start offsets in both texts and the common prefix and suffix lengths
  const lines = [];
  let servedStart = 0;
  let sourceStart = 0;
  for (const [index, servedLine] of servedLines.entries()) {
    const sourceLine = sourceLines[index];
    const shorter = Math.min(servedLine.length, sourceLine.length);
    let prefix = 0;
    while (prefix < shorter && servedLine[prefix] === sourceLine[prefix]) {
      prefix += 1;
    }
    let suffix = 0;
    while (
      suffix < shorter - prefix &&
      servedLine[servedLine.length - 1 - suffix] === sourceLine[sourceLine.length - 1 - suffix]
    ) {
      suffix += 1;
    }

    const changed = servedLine !== sourceLine;
    if (
      changed &&
      (!TOKEN_PATTERN.test(servedLine.slice(prefix, servedLine.length - suffix)) ||
        !TOKEN_PATTERN.test(sourceLine.slice(prefix, sourceLine.length - suffix)))
    ) {
      return undefined;
    }

    lines.push({
      prefix,
      servedLength: servedLine.length,
      servedStart,
      sourceLength: sourceLine.length,
      sourceStart,
      suffix,
    });
    servedStart += servedLine.length + 1;
    sourceStart += sourceLine.length + 1;
  }

  return (offset) => {
    // Last line starting at or before the offset
    let low = 0;
    let high = lines.length - 1;
    while (low < high) {
      const middle = Math.ceil((low + high) / 2);
      if (lines[middle].servedStart <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }

    const line = lines[low];
    const column = offset - line.servedStart;
    if (column <= line.prefix) {
      return line.sourceStart + column;
    }
    if (column >= line.servedLength - line.suffix) {
      return line.sourceStart + line.sourceLength - (line.servedLength - column);
    }

    return line.sourceStart + line.prefix;
  };
};

/**
 * Returns a path relative to the repository when it lies inside it, absolute otherwise.
 * @param {string} path - Path.
 * @returns {string} Display path.
 */
const displayPath = (path) => {
  const repoPath = relative(REPO_ROOT, resolve(path));

  return repoPath.startsWith("..") || isAbsolute(repoPath) ? resolve(path) : repoPath;
};

/**
 * Generates a monocart V8 HTML report and returns its results.
 * @param {string} name - Report name and folder.
 * @param {object[]} entries - V8 entries with repository paths and sources.
 * @param {string} outDir - Report folder.
 * @returns {Promise<object>} Monocart coverage results.
 */
const generateReport = async (name, entries, outDir) => {
  const report = new CoverageReport({
    logging: "error",
    name: `JS coverage (${name})`,
    outputDir: join(outDir, name),
    reports: [["v8"]],
  });
  // Monocart annotates the ranges it reports on, and the merged report reuses the suite entries
  await report.add(structuredClone(entries));

  return report.generate();
};

/**
 * Maps a served script path to its app module path.
 * @param {string} url - Served URL path (`/static/js/...` for e2e, `/ocg-server/static/js/...`
 * for unit).
 * @returns {string} Repository path, such as `ocg-server/static/js/common/dom.js`.
 */
const getModulePath = (url) => {
  const path = url.startsWith(`${UNIT_PATH_PREFIX}/`) ? url.slice(UNIT_PATH_PREFIX.length) : url;

  return `ocg-server${path.replace(CONTENT_HASH_PATTERN, "")}`;
};

/**
 * Merges every entry of a suite per module with monocart's V8 merge.
 * @param {Map<string, object[][]>} files - Function lists per module path, already mapped to the
 * repository source.
 * @param {Map<string, string>} sources - Source per app module path.
 * @returns {Promise<object[]>} One V8 entry per module.
 */
const mergeSuiteEntries = async (files, sources) => {
  const entries = [];
  for (const [file, functionLists] of files) {
    const { functions } = await Util.mergeV8Coverage(functionLists.map((list) => ({ functions: list })));
    entries.push({ functions, source: sources.get(file), url: file });
  }

  return entries;
};

/**
 * Prints the totals and, unless summary is set, the per-file matrix.
 * @param {object} report - Report built by buildReport.
 * @param {boolean} summary - Whether to print counts only.
 */
const printReport = (report, summary = false) => {
  const pct = (value) => (value === null ? "-" : `${value.toFixed(1)}%`);
  const { files, inputs, linesPct, totals } = report;

  console.log(`==> JS coverage of ${APP_MODULES_DIR} (${files.length} modules)`);
  for (const suite of SUITES) {
    const input = inputs[suite];
    console.log(
      `  ${suite}: ${input.rawFiles} raw files, skipped ${input.skippedUnaligned} unaligned, ` +
        `${input.skippedWithoutSource} without source and ${input.skippedOutsideAppModules} outside ` +
        "the app modules",
    );
  }
  console.log(
    `  Lines: e2e ${pct(linesPct.e2e)}, unit ${pct(linesPct.unit)}, merged ${pct(linesPct.merged)}`,
  );
  console.log(`  Modules: ${STATUSES.map((status) => `${status} ${totals[status]}`).join(", ")}`);
  console.log(`  Reports: ${report.reportDir}/{e2e,unit,merged}/index.html`);
  if (summary) {
    return;
  }

  console.log("  Matrix (status, e2e, unit and merged line coverage, module):");
  for (const file of files) {
    const columns = [pct(file.e2eLinesPct), pct(file.unitLinesPct), pct(file.mergedLinesPct)];
    console.log(
      `    ${file.status.padEnd(9)} ${columns.map((column) => column.padStart(6)).join(" ")}  ${file.file}`,
    );
  }
};

/**
 * Reads the source of every app module.
 * @returns {Map<string, string>} Source per repository path, sorted by path.
 */
const readAppModules = () =>
  new Map(
    readdirSync(join(REPO_ROOT, APP_MODULES_DIR), { recursive: true })
      .filter((file) => file.endsWith(".js"))
      .map((file) => join(APP_MODULES_DIR, file).split("\\").join("/"))
      .sort()
      .map((file) => [file, readFileSync(join(REPO_ROOT, file), "utf8")]),
  );

/**
 * Reads a served e2e script from the server's build output.
 * @param {string} url - Served URL path, such as `/static/js/common/dom.<hash>.js`.
 * @returns {string|undefined} Source, or undefined for unit paths and files not in the build.
 */
const readDistSource = (url) => {
  const path = join(REPO_ROOT, DIST_DIR, url);

  return url.startsWith(STATIC_PATH_PREFIX) && existsSync(path) ? readFileSync(path, "utf8") : undefined;
};

/**
 * Parses the command line, resolving folders against the working directory.
 * @returns {{e2e: string[], out: string, summary: boolean, unit: string}} Options.
 */
const readOptions = () => {
  const { values } = parseArgs({
    options: {
      e2e: { multiple: true, type: "string" },
      out: { type: "string" },
      summary: { type: "boolean" },
      unit: { type: "string" },
    },
  });

  return {
    e2e: values.e2e ?? [join(REPO_ROOT, "tests/e2e/test-results/js-coverage/raw")],
    out: values.out ?? join(REPO_ROOT, "tests/e2e/coverage-reports/js-coverage"),
    summary: values.summary ?? false,
    unit: values.unit ?? join(REPO_ROOT, "tests/unit/coverage/raw"),
  };
};

/**
 * Reads the raw coverage folders of a suite and maps every entry to its repository source.
 * Playwright omits the source of scripts it could not read; such entries take the source another
 * entry recorded for the same URL, or else the served file in ocg-server/dist (the content hash
 * pins it), and are skipped when neither exists. Missing folders are reported and skipped.
 * @param {string[]} dirs - Raw coverage folders.
 * @param {Map<string, string>} sources - Source per app module path.
 * @returns {object} Function lists per module path, the folders and the skipped entry counts.
 */
const readSuite = (dirs, sources) => {
  const suite = {
    dirs,
    files: new Map(),
    rawFiles: 0,
    skippedOutside: 0,
    skippedUnaligned: 0,
    skippedWithoutSource: 0,
  };

  // Read every entry first, so entries without a source can borrow one recorded elsewhere
  const entries = [];
  const servedSources = new Map();
  for (const dir of dirs) {
    if (!existsSync(dir)) {
      console.warn(`warning: ${dir} does not exist`);
      continue;
    }

    for (const name of readdirSync(dir).filter((file) => file.endsWith(".json"))) {
      suite.rawFiles += 1;
      for (const entry of JSON.parse(readFileSync(join(dir, name), "utf8"))) {
        entries.push(entry);
        if (typeof entry.source === "string") {
          servedSources.set(entry.url, entry.source);
        }
      }
    }
  }

  for (const { functions, url } of entries) {
    const file = getModulePath(url);
    const source = sources.get(file);
    if (source === undefined) {
      suite.skippedOutside += 1;
      continue;
    }

    const served = servedSources.get(url) ?? readDistSource(url);
    if (served === undefined) {
      suite.skippedWithoutSource += 1;
      continue;
    }

    const mapOffset = createOffsetMapper(served, source);
    if (!mapOffset) {
      suite.skippedUnaligned += 1;
      continue;
    }

    const mapped = functions.map((fn) => ({
      ...fn,
      ranges: fn.ranges.map((range) => ({
        ...range,
        endOffset: mapOffset(range.endOffset),
        startOffset: mapOffset(range.startOffset),
      })),
    }));
    if (!suite.files.has(file)) {
      suite.files.set(file, []);
    }
    suite.files.get(file).push(mapped);
  }

  return suite;
};

try {
  await main();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}

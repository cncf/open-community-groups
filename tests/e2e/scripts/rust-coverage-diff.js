import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

// Compares the Rust line coverage of an e2e run with that of `cargo test -p ocg-server`, both lcov
// files written by `just e2e-rust-coverage`, for the server handlers and services. A line counts
// when the e2e build instruments it, so code compiled only into tests (`#[cfg(test)]` modules and
// tests.rs files) is left out. The lines the e2e run did not reach are listed per file as hit only
// by cargo test or by neither, in a Markdown report. Coverage shows what ran, not what a test
// asserted. The report is informational: it exits non-zero only when an lcov file is missing or
// the e2e lcov has no handler or service lines.
//
// Usage: rust-coverage-diff.js [--e2e FILE] [--unit FILE] [--out FILE]
//   --e2e  - lcov of the e2e run (default: target/llvm-cov/e2e.lcov)
//   --unit - lcov of cargo test (default: target/llvm-cov/unit.lcov)
//   --out  - Markdown report (default: target/llvm-cov/e2e-vs-unit.md)
//   The default folder honors CARGO_TARGET_DIR, as the recipe does.

// Server source areas the report covers: a file of its own and the folder of its submodules.
const AREAS = ["handlers", "services"];
const CATEGORIES = ["unit-only", "neither"];
const CATEGORY_TITLES = { neither: "Hit by neither", "unit-only": "Hit only by cargo test" };
const REPO_ROOT = fileURLToPath(new URL("../../..", import.meta.url));
// Folder `just e2e-rust-coverage` writes the lcov files and the report to.
const REPORT_DIR = join(resolve(REPO_ROOT, process.env.CARGO_TARGET_DIR || "target"), "llvm-cov");
const SERVER_SOURCE_DIR = "ocg-server/src";

/**
 * Reads both lcov files, classifies the server lines and writes the report.
 */
const main = () => {
  const options = readOptions();
  const e2e = filterAreaFiles(readLcov(options.e2e));
  const unit = filterAreaFiles(readLcov(options.unit));
  if (e2e.size === 0) {
    throw new Error(`${options.e2e} has no ${AREAS.join(" or ")} lines; was the server built with coverage?`);
  }

  const report = buildReport(e2e, unit);
  const markdown = renderMarkdown(report, options);
  mkdirSync(dirname(options.out), { recursive: true });
  writeFileSync(options.out, markdown);
  console.log(renderSummaryTable(report.totals).join("\n"));
  console.log(`\nReport written to ${options.out}`);
};

/**
 * Returns the area a server source path belongs to.
 * @param {string} path - Repository-relative source path.
 * @returns {string|undefined} Area name, or undefined outside the reported areas.
 */
const areaOf = (path) =>
  AREAS.find(
    (area) => path === `${SERVER_SOURCE_DIR}/${area}.rs` || path.startsWith(`${SERVER_SOURCE_DIR}/${area}/`),
  );

/**
 * Classifies every line the e2e build instruments as hit by the e2e run, hit only by cargo test,
 * or hit by neither, and groups the lines the e2e run missed into ranges per file.
 * @param {Map<string, Map<number, number>>} e2e - Hit counts per line per file of the e2e run.
 * @param {Map<string, Map<number, number>>} unit - Hit counts per line per file of cargo test.
 * @returns {{files: object[], totals: object[]}} Files with missed lines, and totals per area.
 */
const buildReport = (e2e, unit) => {
  const files = [];
  const totals = new Map([...AREAS, "total"].map((area) => [area, emptyCounts(area)]));

  for (const [path, lines] of [...e2e].sort(([a], [b]) => compareStrings(a, b))) {
    const unitLines = unit.get(path) ?? new Map();
    const counts = emptyCounts(path);
    const ranges = { neither: [], "unit-only": [] };
    let current;

    // Walk the instrumented lines in order; lines without code do not break a range
    for (const line of [...lines.keys()].sort((a, b) => a - b)) {
      counts.lines += 1;
      let category = "e2e";
      if (lines.get(line) === 0) {
        category = (unitLines.get(line) ?? 0) > 0 ? "unit-only" : "neither";
      }
      counts[category] += 1;
      if (category === "e2e") {
        current = undefined;
      } else if (current?.category === category) {
        current.end = line;
      } else {
        current = { category, end: line, start: line };
        ranges[category].push(current);
      }
    }

    for (const key of [areaOf(path), "total"]) {
      for (const field of ["lines", "e2e", ...CATEGORIES]) {
        totals.get(key)[field] += counts[field];
      }
    }
    if (CATEGORIES.some((category) => counts[category] > 0)) {
      files.push({ counts, path, ranges });
    }
  }

  return { files, totals: [...totals.values()] };
};

/**
 * Compares two strings by code point, so the report order does not depend on the locale.
 * @param {string} a - First string.
 * @param {string} b - Second string.
 * @returns {number} Negative, zero or positive.
 */
const compareStrings = (a, b) => {
  if (a === b) {
    return 0;
  }
  return a < b ? -1 : 1;
};

/**
 * Returns zeroed line counts.
 * @param {string} name - Area or file the counts belong to.
 * @returns {{e2e: number, lines: number, name: string, neither: number, "unit-only": number}}
 * Counts.
 */
const emptyCounts = (name) => ({ e2e: 0, lines: 0, name, neither: 0, "unit-only": 0 });

/**
 * Keeps the files of the reported areas.
 * @param {Map<string, Map<number, number>>} files - Hit counts per line per file.
 * @returns {Map<string, Map<number, number>>} Files of the reported areas.
 */
const filterAreaFiles = (files) => new Map([...files].filter(([path]) => areaOf(path)));

/**
 * Formats a count with its share of a total.
 * @param {number} count - Count.
 * @param {number} total - Total.
 * @returns {string} Count and percentage.
 */
const formatShare = (count, total) =>
  total === 0 ? `${count}` : `${count} (${((count / total) * 100).toFixed(1)}%)`;

/**
 * Parses an lcov file into hit counts per line per repository-relative source path. Records of
 * the same file are summed.
 * @param {string} path - lcov file.
 * @returns {Map<string, Map<number, number>>} Hit counts per line per file.
 */
const readLcov = (path) => {
  if (!existsSync(path)) {
    throw new Error(`${path} does not exist; run just e2e-rust-coverage first`);
  }

  const files = new Map();
  let lines;
  for (const record of readFileSync(path, "utf8").split("\n")) {
    if (record.startsWith("SF:")) {
      const source = record.slice(3);
      const file = relative(REPO_ROOT, isAbsolute(source) ? source : resolve(REPO_ROOT, source));
      if (!files.has(file)) {
        files.set(file, new Map());
      }
      lines = files.get(file);
    } else if (record.startsWith("DA:") && lines) {
      const [line, count] = record.slice(3).split(",");
      const lineNumber = Number(line);
      lines.set(lineNumber, (lines.get(lineNumber) ?? 0) + Number(count));
    } else if (record === "end_of_record") {
      lines = undefined;
    }
  }

  return files;
};

/**
 * Parses the command line, resolving paths against the working directory.
 * @returns {{e2e: string, out: string, unit: string}} Options.
 */
const readOptions = () => {
  const { values } = parseArgs({
    options: {
      e2e: { type: "string" },
      out: { type: "string" },
      unit: { type: "string" },
    },
  });

  return {
    e2e: resolve(values.e2e ?? join(REPORT_DIR, "e2e.lcov")),
    out: resolve(values.out ?? join(REPORT_DIR, "e2e-vs-unit.md")),
    unit: resolve(values.unit ?? join(REPORT_DIR, "unit.lcov")),
  };
};

/**
 * Renders the report: the totals, then the missed lines per category with the files that miss
 * the most lines first.
 * @param {{files: object[], totals: object[]}} report - Report from buildReport.
 * @param {{e2e: string, unit: string}} options - lcov files the report compares.
 * @returns {string} Markdown document.
 */
const renderMarkdown = (report, options) => {
  const output = [
    "# Rust coverage: e2e vs cargo test",
    "",
    `Lines of \`${SERVER_SOURCE_DIR}/{${AREAS.join(",")}}\` instrumented in the server binary,`,
    "classified by what reached them. Test-only code is left out. A hit is not",
    "an assertion.",
    "",
    ...renderSummaryTable(report.totals),
    "",
    `- e2e: \`${options.e2e}\``,
    `- cargo test: \`${options.unit}\``,
  ];

  for (const category of CATEGORIES) {
    const files = report.files
      .filter((file) => file.counts[category] > 0)
      .sort((a, b) => b.counts[category] - a.counts[category] || compareStrings(a.path, b.path));
    output.push("", `## ${CATEGORY_TITLES[category]}`, "");
    if (files.length === 0) {
      output.push("None.");
      continue;
    }
    output.push("| File | Lines | Ranges |", "| --- | ---: | --- |");
    for (const file of files) {
      const ranges = file.ranges[category]
        .map(({ end, start }) => (start === end ? `${start}` : `${start}-${end}`))
        .join(", ");
      output.push(`| \`${file.path}\` | ${file.counts[category]} | ${ranges} |`);
    }
  }

  return `${output.join("\n")}\n`;
};

/**
 * Renders the totals per area as a Markdown table.
 * @param {object[]} totals - Counts per area and in total.
 * @returns {string[]} Table lines.
 */
const renderSummaryTable = (totals) => [
  "| Area | Lines | e2e | cargo test only | Neither |",
  "| --- | ---: | ---: | ---: | ---: |",
  ...totals.map(
    (counts) =>
      `| ${counts.name} | ${counts.lines} | ${formatShare(counts.e2e, counts.lines)} | ` +
      `${formatShare(counts["unit-only"], counts.lines)} | ${formatShare(counts.neither, counts.lines)} |`,
  ),
];

try {
  main();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}

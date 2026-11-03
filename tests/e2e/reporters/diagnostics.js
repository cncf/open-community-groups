import { appendFile } from "node:fs/promises";
import * as path from "node:path";

// Annotation types summarized by this reporter, in output order.
const DIAGNOSTIC_TYPES = ["browser-health", "browser-health-allowed", "navigation-retry"];

// Entries listed per type before the rest are only counted.
const MAX_LISTED_ENTRIES = 100;

/**
 * Playwright reporter that groups diagnostic annotations (`browser-health`, `browser-health-allowed`,
 * `navigation-retry`) by type, prints a summary at the end of the run and appends it to
 * `$GITHUB_STEP_SUMMARY` when set. It never changes the run status: errors are only logged.
 */
export default class DiagnosticsReporter {
  constructor() {
    this.entriesByType = new Map(DIAGNOSTIC_TYPES.map((type) => [type, []]));
    this.rootDir = process.cwd();
    this.testResults = 0;
  }

  onBegin(config) {
    this.rootDir = config.rootDir;
  }

  onTestEnd(test, result) {
    this.testResults += 1;
    for (const annotation of result.annotations ?? []) {
      this.entriesByType.get(annotation.type)?.push({
        description: annotation.description ?? "",
        retry: result.retry,
        test: describeTest(test, this.rootDir),
      });
    }
  }

  async onEnd() {
    // Nothing ran (for example `--list`), so there is nothing to summarize.
    if (this.testResults === 0) {
      return;
    }

    try {
      const summary = buildSummary(this.entriesByType);
      console.log(`\n${summary}`);

      if (process.env.GITHUB_STEP_SUMMARY) {
        await appendFile(process.env.GITHUB_STEP_SUMMARY, `${summary}\n`);
      }
    } catch (error) {
      console.error(`diagnostics reporter: ${error.message}`);
    }
  }

  printsToStdio() {
    return false;
  }
}

/** Builds the Markdown summary, one section per annotation type with its count and entries. */
const buildSummary = (entriesByType) => {
  const lines = ["## E2E diagnostics"];

  for (const [type, entries] of entriesByType) {
    lines.push("", `### ${type} (${entries.length})`, "");

    if (entries.length === 0) {
      lines.push("None.");
      continue;
    }

    const sortedEntries = entries.toSorted((a, b) => a.test.localeCompare(b.test) || a.retry - b.retry);
    for (const { description, retry, test } of sortedEntries.slice(0, MAX_LISTED_ENTRIES)) {
      const attempt = retry > 0 ? ` (retry ${retry})` : "";
      lines.push(`- ${test}${attempt}: ${description}`);
    }
    if (entries.length > MAX_LISTED_ENTRIES) {
      lines.push(`- ... and ${entries.length - MAX_LISTED_ENTRIES} more`);
    }
  }

  return lines.join("\n");
};

/** Describes a test as `[project] file:line › describe › title`, with the file relative to the root dir. */
const describeTest = (test, rootDir) => {
  const [, projectName, , ...titles] = test.titlePath();
  const file = path.relative(rootDir, test.location.file);

  const project = projectName ? `[${projectName}] ` : "";

  return `${project}${file}:${test.location.line} › ${titles.join(" › ")}`;
};

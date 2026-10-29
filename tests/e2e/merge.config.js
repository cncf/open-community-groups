import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "@playwright/test";

// Config for `npx playwright merge-reports --config merge.config.js blob-report`, which merges the
// blob reports of CI shards. It only sets the reporters and the root used to resolve test paths.

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Output folder for the merged HTML and JSON reports.
const mergedReportDir = path.resolve(__dirname, "merged-report");

export default defineConfig({
  testDir: __dirname,
  reporter: [
    ["html", { open: "never", outputFolder: path.join(mergedReportDir, "html") }],
    ["json", { outputFile: path.join(mergedReportDir, "results.json") }],
    [path.resolve(__dirname, "reporters/diagnostics.js")],
  ],
});

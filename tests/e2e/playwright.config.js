import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, devices } from "@playwright/test";

import { bindWorkerToStack, getE2eStacks } from "./stacks.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Isolated stacks for parallel runs; must be bound before the contract below is read.
const stacks = getE2eStacks();
bindWorkerToStack(stacks);

// Base URL used by browser contexts and the optional web server health check.
const baseURL = process.env.OCG_E2E_BASE_URL || "http://127.0.0.1:9001";
// Whether Playwright starts the application server itself.
const shouldStartServer = process.env.OCG_E2E_START_SERVER === "true";
// Whether an already running server is reused instead of booting a new one.
const shouldReuseExistingServer = process.env.OCG_E2E_REUSE_SERVER === "true";
// Command used to start the application server before the suite begins.
const webServerCommand = process.env.OCG_E2E_SERVER_CMD;
// Maximum time to wait for the application server to become reachable.
const webServerTimeout = Number(process.env.OCG_E2E_SERVER_TIMEOUT || 300_000);
// Repository root used as the working directory for the server command.
const webServerCwd = path.resolve(__dirname, "../..");
// Output folder for Playwright's HTML report.
const reportDir = path.resolve(__dirname, "playwright-report");
// Output folder for the blob report written in CI, merged into one report by `merge.config.js`.
const blobReportDir = path.resolve(__dirname, "blob-report");
// Output folder for Playwright artifacts such as traces and screenshots.
const resultsDir = path.resolve(__dirname, "test-results");
// Reporter summarizing browser-health and navigation-retry annotations; never changes the exit status.
const diagnosticsReporterPath = path.resolve(__dirname, "reporters/diagnostics.js");
// Preflight script that aborts the run unless the server and psql target the same database.
const preflightPath = path.resolve(__dirname, "preflight.js");
// Deterministic browser environment for stable ARIA snapshots, shared by the smoke projects.
const deepUseOverrides = {
  colorScheme: "light",
  locale: "en-US",
  reducedMotion: "reduce",
  timezoneId: "UTC",
};
// Tag that restricts a test to the mobile project.
const mobileTestPattern = /@mobile/;
// Tag that adds a desktop test to the Firefox and WebKit smoke projects.
const smokeTestPattern = /@smoke/;

const webServer =
  shouldStartServer && webServerCommand
    ? {
        command: webServerCommand,
        cwd: webServerCwd,
        url: baseURL,
        reuseExistingServer: shouldReuseExistingServer,
        timeout: webServerTimeout,
      }
    : undefined;

export default defineConfig({
  testDir: __dirname,
  globalSetup: preflightPath,
  // Each worker owns a stack and every test owns the rows it changes, so the tests of one file can
  // run on different stacks.
  fullyParallel: true,
  // Tests share their stack's database, so each worker needs a stack of its own.
  workers: Math.max(stacks.length, 1),
  // Fail CI runs that would silently skip tests because of a stray test.only.
  forbidOnly: !!process.env.CI,
  retries: 0,
  expect: {
    // ARIA snapshot files (`toMatchAriaSnapshot({ name })`) sit next to their spec and are shared
    // by every project, so a desktop and a mobile test can match the same file.
    toMatchAriaSnapshot: { pathTemplate: "{testFileDir}/{testFileName}-snapshots/{arg}{ext}" },
  },
  // CI runs write blob reports for the merge-reports job (parallel.sh moves them into the run archive
  // with OCG_E2E_RUN_ARCHIVE); local runs keep the HTML report.
  reporter: process.env.CI
    ? [["blob", { outputDir: blobReportDir }], ["list"], [diagnosticsReporterPath]]
    : [["html", { open: "never", outputFolder: reportDir }], ["list"], [diagnosticsReporterPath]],
  outputDir: resultsDir,
  use: {
    baseURL,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    // Failure traces already hold the page snapshots; videos only slow the runs down.
    video: "off",
  },
  projects: [
    {
      name: "firefox-smoke",
      grep: smokeTestPattern,
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Firefox"], ...deepUseOverrides },
    },
    {
      name: "webkit-smoke",
      grep: smokeTestPattern,
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Safari"], ...deepUseOverrides },
    },
    {
      name: "chromium-deep",
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Chrome"], ...deepUseOverrides },
    },
    {
      name: "chromium-mobile-deep",
      grep: mobileTestPattern,
      // The iPhone device descriptor defaults to WebKit; keep the deep suite on Chromium.
      use: { ...devices["iPhone 12"], browserName: "chromium", ...deepUseOverrides },
    },
  ],
  webServer,
});

import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, devices } from "@playwright/test";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

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
// Output folder for Playwright artifacts such as traces and videos.
const resultsDir = path.resolve(__dirname, "test-results");
// Preflight script that aborts the run unless the server and psql target the same database.
const preflightPath = path.resolve(__dirname, "preflight.js");
// Fast cross-browser specs that make up the smoke projects.
const smokeSpecPaths = [
  "workflows/navigation/navigation.spec.js",
  "dashboard/common/dashboard.spec.js",
  "site/common/header.spec.js",
];
// Deep runs need a deterministic browser environment for stable snapshots.
const deepUseOverrides = {
  colorScheme: "light",
  locale: "en-US",
  reducedMotion: "reduce",
  timezoneId: "UTC",
};
// Tag that restricts a test to the mobile project.
const mobileTestPattern = /@mobile/;

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
  fullyParallel: false,
  workers: 1,
  retries: 0,
  expect: {
    toHaveScreenshot: { maxDiffPixelRatio: 0.03 },
  },
  reporter: [["html", { open: "never", outputFolder: reportDir }], ["list"]],
  outputDir: resultsDir,
  snapshotPathTemplate: "{testFileDir}/{testFileName}-snapshots/{arg}-{projectName}{ext}",
  use: {
    baseURL,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium-smoke",
      testMatch: smokeSpecPaths,
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "firefox-smoke",
      testMatch: smokeSpecPaths,
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Firefox"] },
    },
    {
      name: "webkit-smoke",
      testMatch: smokeSpecPaths,
      grepInvert: mobileTestPattern,
      use: { ...devices["Desktop Safari"] },
    },
    {
      name: "chromium-deep",
      testIgnore: smokeSpecPaths,
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
